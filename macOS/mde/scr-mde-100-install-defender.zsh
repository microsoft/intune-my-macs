#!/bin/zsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#set -x

############################################################################################
## IMM - Install Microsoft Defender for Endpoint (PKG)
##
## Version: 1.0.0
##
## Summary
## - Downloads and installs the latest Microsoft Defender for Endpoint for macOS (PKG).
## - Ensures Microsoft 365 core apps (optional list) have finished installing first (to avoid network extension impact).
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
pkg="$tempdir/MicrosoftDefender.pkg"                                                  # Fixed local download path
log="$logandmetadir/$appname.log"                                                     # Log file
metafile="$logandmetadir/$appname.meta"                                               # Stores last-modified date

cleanup() {
  [[ -d "$tempdir" ]] && rm -rf "$tempdir"
}
trap cleanup EXIT

startLog() {
  if [[ ! -d "$logandmetadir" ]]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Creating [$logandmetadir]"
    mkdir -p "$logandmetadir"
  fi
  exec > >(tee -a "$log") 2>&1
}

updateOctory () {
  # Update Octory monitor state if Octory installed & running
  if [[ -a "/Library/Application Support/Octory" ]]; then
    if pgrep -i "Octory" >/dev/null 2>&1; then
      echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Updating Octory monitor for [$appname] to [$1]"
      /usr/local/bin/octo-notifier monitor "$appname" --state $1 >/dev/null 2>&1 || true
    fi
  fi
}

waitForProcess () {
  local processName="$1"; local fixedDelay="$2"; local terminate="$3"
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Waiting for other [$processName] processes to end"
  while pgrep -f "$processName" >/dev/null 2>&1; do
    if [[ $terminate == "true" ]]; then
      local pid=$(pgrep -f "$processName" | head -n1)
      [[ -n $pid ]] && echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | + Terminating [$processName] pid [$pid]" && kill -9 $pid 2>/dev/null || true
      return
    fi
    local delay
    if [[ -z $fixedDelay ]]; then delay=$(( RANDOM % 50 + 10 )); else delay=$fixedDelay; fi
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") |  + Still running, waiting [$delay]s"
    sleep $delay
  done
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | No instances of [$processName] found"
}

fetchLastModifiedDate () {
  [[ ! -d "$logandmetadir" ]] && mkdir -p "$logandmetadir"
  lastmodified=$(curl -sIL "$weburl" | grep -i "last-modified" | awk '{$1=""; sub(/^[ \t]+/, ""); print}' | tr -d '\r')
  if [[ $1 == "update" && -n $lastmodified ]]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Writing last modified [$lastmodified] to [$metafile]"
    echo "$lastmodified" > "$metafile"
  fi
}

downloadApp () {
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Downloading [$appname] from [$weburl]"
  # Download to a fixed local path; the remote filename returned by the FWLink
  # (e.g. wdav.pkg) does not affect success.
  if ! curl -fSL --connect-timeout 30 --retry 3 --retry-delay 10 -o "$pkg" "$weburl"; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Download failed"
    updateOctory failed
    exit 1
  fi
  # Sanity check: the download must be a PKG installer (xar archive)
  if [[ "$(file -b "$pkg")" != *"xar archive"* ]]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Downloaded file is not a PKG installer. Aborting."
    updateOctory failed
    exit 1
  fi
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Downloaded to [$pkg]"
}

updateCheck () {
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Evaluating install/update requirement"
  if [[ -d "/Applications/$app" ]]; then
    if [[ $autoUpdate == "true" ]]; then
      echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | [$appname] already installed and self-updating; exiting"
      exit 0
    fi
    fetchLastModifiedDate
    if [[ -f "$metafile" ]]; then
      previous=$(cat "$metafile")
      if [[ "$previous" != "$lastmodified" && -n $lastmodified ]]; then
        echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Update required (prev=[$previous] current=[$lastmodified])"
      else
        echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | No update required; exiting"
        exit 0
      fi
    else
      echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | No meta file; proceeding with (re)install"
    fi
  else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Not installed; proceeding"
  fi
}

waitForOtherApps () {
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Waiting for prerequisite apps (if missing)"
  local pending=1
  local attempt=0
  while [[ $pending -eq 1 && $attempt -lt 30 ]]; do
    pending=0
    for a in "${waitForTheseApps[@]}"; do
      if [[ ! -e "$a" ]]; then
        echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") |  + Waiting for [$a]"; pending=1; break
      fi
    done
    if [[ $pending -eq 1 ]]; then
      attempt=$(( attempt + 1 ))
      sleep 30
    fi
  done
  if [[ $pending -eq 0 ]]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | All prerequisite apps present (or timeout reached)"
  else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Proceeding after max wait attempts"
  fi
}

waitForDesktop () {
  until pgrep -f "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock" >/dev/null 2>&1; do
    local delay=$(( RANDOM % 50 + 10 ))
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") |  + Dock not running, waiting [$delay]s"
    sleep $delay
  done
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Dock available"
}

installPKG () {
  waitForProcess "$processpath" "300" "$terminateprocess"
  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Installing [$appname]"
  updateOctory installing
  # Defender PKG expects root target
  installer -pkg "$pkg" -target /
  if [[ $? -eq 0 ]]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Install complete"
    fetchLastModifiedDate update
    updateOctory installed
    return 0
  else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Install failed"
    updateOctory failed
    return 1
  fi
}

# ------------------- Script Body -------------------
startLog

echo ""; echo "##############################################################"; echo "# $(date -u "+%Y-%m-%d %H:%M:%S UTC") | Logging install of [$appname] to [$log]"; echo "############################################################"; echo ""

updateCheck
waitForDesktop
waitForOtherApps
downloadApp
installPKG || exit 1

echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Success"; exit 0
