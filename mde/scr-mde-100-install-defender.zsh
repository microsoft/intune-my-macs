#!/bin/zsh
#set -x

############################################################################################
## IMM - Install Microsoft Defender for Endpoint (PKG)
##
## Version: 1.0.0
## Maintainer: neiljohn@microsoft.com
##
## Summary
## - Downloads and installs the latest Microsoft Defender for Endpoint for macOS (PKG).
## - Ensures Microsoft 365 core apps (optional list) have finished installing first (to avoid network extension impact).
## - Installs Rosetta 2 on Apple silicon if required.
## - Skips install if already present and autoUpdate=true.
## - Uses HTTP Last-Modified header + local meta file to decide if update required.
## - Updates Octory status when Octory is installed and running.
## - Logs to /Library/Logs/Microsoft/IntuneScripts/installDefender/Microsoft Defender.log
##
## Exit codes
## 0 = Success (installed or already current / autoUpdate true)
## 1 = Failure
############################################################################################

## Copyright (c) 2020 Microsoft Corp. All rights reserved.
## Provided AS IS without warranty of any kind. Use at your own risk.

# User Defined variables
weburl="https://go.microsoft.com/fwlink/?linkid=2097502"                              # FWLink for latest Defender PKG
appname="Microsoft Defender"                                                          # Used for logging & Octory
app="Microsoft Defender.app"                                                          # Application bundle name
logandmetadir="/Library/Logs/Microsoft/IntuneScripts/installDefender"                 # Log + meta directory
processpath="/Applications/Microsoft Defender.app/Contents/MacOS/Microsoft Defender"  # Primary process path
terminateprocess="true"                                                               # Kill if running (true/false)
autoUpdate="true"                                                                     # Defender self-updates via channel
waitForTheseApps=( \
  "/Applications/Microsoft Edge.app" \
  "/Applications/Microsoft Outlook.app" \
  "/Applications/Microsoft Word.app" \
  "/Applications/Microsoft Excel.app" \
  "/Applications/Microsoft PowerPoint.app" \
  "/Applications/Microsoft OneNote.app" \
  "/Applications/Company Portal.app" )                                                # Optional dependency list

# Generated variables
tempdir=$(mktemp -d)
log="$logandmetadir/$appname.log"                                                     # Log file
metafile="$logandmetadir/$appname.meta"                                               # Stores last-modified date

cleanup() {
  [[ -d "$tempdir" ]] && rm -rf "$tempdir"
}
trap cleanup EXIT

startLog() {
  if [[ ! -d "$logandmetadir" ]]; then
    echo "$(date) | Creating [$logandmetadir]"
    mkdir -p "$logandmetadir"
  fi
  exec > >(tee -a "$log") 2>&1
}

updateOctory () {
  # Update Octory monitor state if Octory installed & running
  if [[ -a "/Library/Application Support/Octory" ]]; then
    if pgrep -i "Octory" >/dev/null 2>&1; then
      echo "$(date) | Updating Octory monitor for [$appname] to [$1]"
      /usr/local/bin/octo-notifier monitor "$appname" --state $1 >/dev/null 2>&1 || true
    fi
  fi
}

waitForProcess () {
  local processName="$1"; local fixedDelay="$2"; local terminate="$3"
  echo "$(date) | Waiting for other [$processName] processes to end"
  while pgrep -f "$processName" >/dev/null 2>&1; do
    if [[ $terminate == "true" ]]; then
      local pid=$(pgrep -f "$processName" | head -n1)
      [[ -n $pid ]] && echo "$(date) | + Terminating [$processName] pid [$pid]" && kill -9 $pid 2>/dev/null || true
      return
    fi
    local delay
    if [[ -z $fixedDelay ]]; then delay=$(( RANDOM % 50 + 10 )); else delay=$fixedDelay; fi
    echo "$(date) |  + Still running, waiting [$delay]s"
    sleep $delay
  done
  echo "$(date) | No instances of [$processName] found"
}

checkForRosetta2 () {
  echo "$(date) | Checking for Rosetta 2"
  waitForProcess "/usr/sbin/softwareupdate"
  local osvers_major osvers_minor osvers_dot
  IFS='.' read osvers_major osvers_minor osvers_dot <<< "$(/usr/bin/sw_vers -productVersion)"
  if [[ ${osvers_major} -ge 11 ]]; then
    if /usr/sbin/sysctl -n machdep.cpu.brand_string | grep -q "Intel"; then
      echo "$(date) | Intel CPU detected - Rosetta not needed"
    else
      if pgrep oahd >/dev/null 2>&1; then
        echo "$(date) | Rosetta already installed"
      else
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license && \
          echo "$(date) | Rosetta installed" || echo "$(date) | Rosetta install failed"
      fi
    fi
  else
    echo "$(date) | macOS < 11 - Rosetta not required"
  fi
}

fetchLastModifiedDate () {
  [[ ! -d "$logandmetadir" ]] && mkdir -p "$logandmetadir"
  lastmodified=$(curl -sIL "$weburl" | grep -i "last-modified" | awk '{$1=""; sub(/^[ \t]+/, ""); print}' | tr -d '\r')
  if [[ $1 == "update" && -n $lastmodified ]]; then
    echo "$(date) | Writing last modified [$lastmodified] to [$metafile]"
    echo "$lastmodified" > "$metafile"
  fi
}

downloadApp () {
  echo "$(date) | Downloading [$appname] from [$weburl]"
  cd "$tempdir" || { echo "$(date) | Failed to cd to temp dir"; exit 1; }
  curl -f -s --connect-timeout 30 --retry 5 --retry-delay 60 -L -J -O "$weburl"
  if [[ $? -ne 0 ]]; then
    echo "$(date) | Download failed"
    updateOctory failed
    exit 1
  fi
  # Identify downloaded file
  for f in *; do tempfile="$PWD/$f"; done
  case $tempfile in
    *.pkg|*.PKG) packageType="PKG" ;;
    *) echo "$(date) | Unexpected file type: $tempfile"; exit 1 ;;
  esac
  echo "$(date) | Downloaded to [$tempfile] (type=$packageType)"
}

updateCheck () {
  echo "$(date) | Evaluating install/update requirement"
  if [[ -d "/Applications/$app" ]]; then
    if [[ $autoUpdate == "true" ]]; then
      echo "$(date) | [$appname] already installed and self-updating; exiting"
      exit 0
    fi
    fetchLastModifiedDate
    if [[ -f "$metafile" ]]; then
      previous=$(cat "$metafile")
      if [[ "$previous" != "$lastmodified" && -n $lastmodified ]]; then
        echo "$(date) | Update required (prev=[$previous] current=[$lastmodified])"
      else
        echo "$(date) | No update required; exiting"
        exit 0
      fi
    else
      echo "$(date) | No meta file; proceeding with (re)install"
    fi
  else
    echo "$(date) | Not installed; proceeding"
  fi
}

waitForOtherApps () {
  echo "$(date) | Waiting for prerequisite apps (if missing)"
  local pending=1
  local attempt=0
  while [[ $pending -eq 1 && $attempt -lt 30 ]]; do
    pending=0
    for a in "${waitForTheseApps[@]}"; do
      if [[ ! -e "$a" ]]; then
        echo "$(date) |  + Waiting for [$a]"; pending=1; break
      fi
    done
    if [[ $pending -eq 1 ]]; then
      attempt=$(( attempt + 1 ))
      sleep 30
    fi
  done
  if [[ $pending -eq 0 ]]; then
    echo "$(date) | All prerequisite apps present (or timeout reached)"
  else
    echo "$(date) | Proceeding after max wait attempts"
  fi
}

waitForDesktop () {
  until pgrep -f "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock" >/dev/null 2>&1; do
    local delay=$(( RANDOM % 50 + 10 ))
    echo "$(date) |  + Dock not running, waiting [$delay]s"
    sleep $delay
  done
  echo "$(date) | Dock available"
}

installPKG () {
  waitForProcess "$processpath" "300" "$terminateprocess"
  echo "$(date) | Installing [$appname]"
  updateOctory installing
  # Defender PKG expects root target
  installer -pkg "$tempfile" -target /
  if [[ $? -eq 0 ]]; then
    echo "$(date) | Install complete"
    fetchLastModifiedDate update
    updateOctory installed
    return 0
  else
    echo "$(date) | Install failed"
    updateOctory failed
    return 1
  fi
}

# ------------------- Script Body -------------------
startLog

echo ""; echo "##############################################################"; echo "# $(date) | Logging install of [$appname] to [$log]"; echo "############################################################"; echo ""

checkForRosetta2
updateCheck
waitForDesktop
waitForOtherApps
downloadApp
installPKG || exit 1

echo "$(date) | Success"; exit 0
