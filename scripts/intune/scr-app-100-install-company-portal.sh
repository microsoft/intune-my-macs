#!/bin/zsh
#set -x

############################################################################################
## IMM - Install Company Portal (PKG)
##
## Version: 1.0.0
## Maintainer: neiljohn@microsoft.com
##
## Summary
## - Downloads and installs Microsoft Company Portal on macOS using a signed PKG.
## - Installs Microsoft Auto Update (MAU) first to ensure update channel is available.
## - On Apple silicon, ensures Rosetta 2 is present (installs if required).
## - If Company Portal is already installed and autoUpdate=true, exits without changes.
## - Otherwise performs an update check via HTTP Last-Modified and a local meta file, then installs/updates.
## - Optionally terminates running Company Portal process before install when configured.
## - Updates Octory status when Octory is installed and running.
## - Detailed logging written to /Library/Logs/Microsoft/IntuneScripts/installCompanyPortal/Company Portal.log
##
## Inputs (variables)
## - weburl: Download URL for the Company Portal PKG
## - mauurl: Download URL for the Microsoft Auto Update PKG
## - appname, app, processpath, terminateprocess, autoUpdate
##
## Artifacts (outputs)
## - Log: /Library/Logs/Microsoft/IntuneScripts/installCompanyPortal/Company Portal.log
## - Meta: /Library/Logs/Microsoft/IntuneScripts/installCompanyPortal/Company Portal.meta (Last-Modified)
##
## Requirements
## - macOS 11 or later
## - Root privileges
## - Built-ins: curl, installer, softwareupdate, rsync
##
## Exit codes
## - 0: Success (installed or no action required)
## - 1: Failure (download/install error or unsupported package type)
##
## Usage
## - Run as root via Intune device script or your management workflow.
############################################################################################

## Copyright (c) 2020 Microsoft Corp. All rights reserved.
## Scripts are not supported under any Microsoft standard support program or service. The scripts are provided AS IS without warranty of any kind.
## Microsoft disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a
## particular purpose. The entire risk arising out of the use or performance of the scripts and documentation remains with you. In no event shall
## Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
## (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary
## loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility
## of such damages.
## Feedback: neiljohn@microsoft.com

# User Defined variables
mauurl="https://go.microsoft.com/fwlink/?linkid=830196"                         # URL to fetch latest MAU
weburl="https://go.microsoft.com/fwlink/?linkid=853070"                         # What is the Azure Blob Storage URL?
appname="Company Portal"                                                        # The name of our App deployment script (also used for Octory monitor)
app="Company Portal.app"                                                        # The actual name of our App once installed
logandmetadir="/Library/Logs/Microsoft/IntuneScripts/installCompanyPortal"      # The location of our logs and last updated data
processpath="/Applications/Company Portal.app/Contents/MacOS/Company Portal"    # The process name of the App we are installing
terminateprocess="true"                                                         # Do we want to terminate the running process? If false we'll wait until its not running
autoUpdate="true"                                                               # Application updates itself, if already installed we should exit

# Generated variables
tempdir=$(mktemp -d)
log="$logandmetadir/$appname.log"                                               # The location of the script log file
metafile="$logandmetadir/$appname.meta"                                         # The location of our meta file (for updates)

# Helpers

cleanup() {
    if [[ -d "$tempdir" ]]; then
        rm -rf "$tempdir"
    fi
}
trap cleanup EXIT

updateMAU () {
    #################################################################################################################
    #################################################################################################################
    ##  This function downloads and installs the latest Microsoft Auto Update (MAU) tool 
    ##
    echo "$(date) | Starting downlading of [MAU]"

    cd "$tempdir"
    curl -o "$tempdir/mau.pkg" -f -s --connect-timeout 30 --retry 5 --retry-delay 60 -L -J -O "$mauurl"
    if [[ $? == 0 ]]; then
        echo "$(date) | Downloaded [$mauurl] to [$tempdir/mau.pkg]"
        echo "$(date) | Starting installation of latest MAU"
        installer -pkg "$tempdir/mau.pkg" -target /
        if [ "$?" = "0" ]; then
            echo "$(date) | MAU Installed"
            echo "$(date) | Cleaning Up"
            rm -rf "$tempdir/mau.pkg"
        else
            echo "$(date) | Failed to install [MAU]"
            echo "$(date) | Cleaning Up"
            rm -rf "$tempdir/mau.pkg"
        fi
    else
        echo "$(date) | Failure to download [MAU]"
        exit 1
    fi
}

# function to delay script if the specified process is running
waitForProcess () {
    #################################################################################################################
    #################################################################################################################
    ##  Function to pause while a specified process is running
    ##  $1 = name of process to check for; $2 = delay; $3 = terminate true/false
    processName=$1
    fixedDelay=$2
    terminate=$3

    echo "$(date) | Waiting for other [$processName] processes to end"
    while ps aux | grep "$processName" | grep -v grep &>/dev/null; do
        if [[ $terminate == "true" ]]; then
            pid=$(pgrep -f "$processName" | head -n1)
            if [[ -n "$pid" ]]; then
                echo "$(date) | + [$appname] running, terminating [$processName] at pid [$pid]..."
                kill -9 $pid 2>/dev/null || true
            fi
            return
        fi
        if [[ ! $fixedDelay ]]; then
            delay=$(( $RANDOM % 50 + 10 ))
        else
            delay=$fixedDelay
        fi
        echo "$(date) |  + Another instance of $processName is running, waiting [$delay] seconds"
        sleep $delay
    done
    echo "$(date) | No instances of [$processName] found, safe to proceed"
}

# check if we need Rosetta 2
checkForRosetta2 () {
    #################################################################################################################
    #################################################################################################################
    echo "$(date) | Checking if we need Rosetta 2 or not"
    waitForProcess "/usr/sbin/softwareupdate"
    OLDIFS=$IFS
    IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(/usr/bin/sw_vers -productVersion)"
    IFS=$OLDIFS
    if [[ ${osvers_major} -ge 11 ]]; then
        processor=$(/usr/sbin/sysctl -n machdep.cpu.brand_string | grep -o "Intel")
        if [[ -n "$processor" ]]; then
            echo "$(date) | $processor processor installed. No need to install Rosetta."
        else
            if /usr/bin/pgrep oahd >/dev/null 2>&1; then
                echo "$(date) | Rosetta is already installed and running. Nothing to do."
            else
                /usr/sbin/softwareupdate --install-rosetta --agree-to-license
                if [[ $? -eq 0 ]]; then
                    echo "$(date) | Rosetta has been successfully installed."
                else
                    echo "$(date) | Rosetta installation failed!"
                fi
            fi
        fi
    else
        echo "$(date) | Mac is running macOS $osvers_major.$osvers_minor.$osvers_dot_version. No need to install Rosetta."
    fi
}

# Update the last modified date for this app
fetchLastModifiedDate() {
    if [[ ! -d "$logandmetadir" ]]; then
        echo "$(date) | Creating [$logandmetadir] to store metadata"
        mkdir -p "$logandmetadir"
    fi
    lastmodified=$(curl -sIL "$weburl" | grep -i "last-modified" | awk '{$1=""; print $0}' | awk '{ sub(/^[ \t]+/, ""); print }' | tr -d '\r')
    if [[ $1 == "update" ]]; then
        echo "$(date) | Writing last modified date [$lastmodified] to [$metafile]"
        echo "$lastmodified" > "$metafile"
    fi
}

# Download PKG
downloadApp () {
    echo "$(date) | Starting downlading of [$appname]"
    echo "$(date) | Downloading $appname [$weburl]"

    cd "$tempdir"
    curl -f -s --connect-timeout 30 --retry 5 --retry-delay 60 --compressed -L -J -O "$weburl"
    if [[ $? == 0 ]]; then
        for f in *; do
            tempfile=$f
            echo "$(date) | Found downloaded tempfile [$tempfile]"
        done
        case $tempfile in
            *.pkg|*.PKG|*.mpkg|*.MPKG)
                packageType="PKG"
                ;;
            *)
                echo "$(date) | Expected a PKG, but downloaded an unsupported type [$tempfile]"
                exit 1
                ;;
        esac
        echo "$(date) | Downloaded [$app] to [$tempfile]"
        echo "$(date) | Detected install type as [$packageType]"
    else
        echo "$(date) | Failure to download [$weburl]"
        updateOctory failed
        exit 1
    fi
}

# Check if we need to update or not
updateCheck() {
    echo "$(date) | Checking if we need to install or update [$appname]"
    if [ -d "/Applications/$app" ]; then
        if [[ $autoUpdate == "true" ]]; then
            echo "$(date) | [$appname] is already installed and handles updates itself, exiting"
            exit 0
        fi
        echo "$(date) | [$appname] already installed, let's see if we need to update"
        fetchLastModifiedDate
        if [[ -d "$logandmetadir" ]]; then
            if [ -f "$metafile" ]; then
                previouslastmodifieddate=$(cat "$metafile")
                if [[ "$previouslastmodifieddate" != "$lastmodified" ]]; then
                    echo "$(date) | Update found, previous [$previouslastmodifieddate] and current [$lastmodified]"
                    update="update"
                else
                    echo "$(date) | No update between previous [$previouslastmodifieddate] and current [$lastmodified]"
                    echo "$(date) | Exiting, nothing to do"
                    exit 0
                fi
            else
                echo "$(date) | Meta file [$metafile] not found"
                echo "$(date) | Unable to determine if update required, updating [$appname] anyway"
            fi
        fi
    else
        echo "$(date) | [$appname] not installed, need to download and install"
    fi
}

## Install PKG Function (PKG-only path)
installPKG () {
    waitForProcess "$processpath" "300" "$terminateprocess"
    echo "$(date) | Installing $appname"
    updateOctory installing

    if [[ -d "/Applications/$app" ]]; then
        rm -rf "/Applications/$app"
    fi

    installer -pkg "$tempfile" -target /Applications
    if [ "$?" = "0" ]; then
        echo "$(date) | $appname Installed"
        echo "$(date) | Cleaning Up"
        rm -rf "$tempdir"
        echo "$(date) | Application [$appname] succesfully installed"
        fetchLastModifiedDate update
        updateOctory installed
        exit 0
    else
        echo "$(date) | Failed to install $appname"
        rm -rf "$tempdir"
        updateOctory failed
        exit 1
    fi
}

updateOctory () {
    #################################################################################################################
    #################################################################################################################
    ##  Update Octory status (if required)
    if [[ -a "/Library/Application Support/Octory" ]]; then
        if [[ $(ps aux | grep -i "Octory" | grep -v grep) ]]; then
            echo "$(date) | Updating Octory monitor for [$appname] to [$1]"
            /usr/local/bin/octo-notifier monitor "$appname" --state $1 >/dev/null
        fi
    fi
}

startLog() {
    if [[ ! -d "$logandmetadir" ]]; then
        echo "$(date) | Creating [$logandmetadir] to store logs"
        mkdir -p "$logandmetadir"
    fi
    exec > >(tee -a "$log") 2>&1
}

# delay until the user has finished setup assistant.
waitForDesktop () {
  until ps aux | grep /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -v grep &>/dev/null; do
    delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  + Dock not running, waiting [$delay] seconds"
    sleep $delay
  done
  echo "$(date) | Dock is here, lets carry on"
}

###################################################################################
###################################################################################
## Begin Script Body
###################################################################################
###################################################################################

startLog

echo ""
echo "##############################################################"
echo "# $(date) | Logging install of [$appname] to [$log]"
echo "############################################################"
echo ""

checkForRosetta2
updateCheck
waitForDesktop

downloadApp
updateMAU

# PKG only
if [[ $packageType == "PKG" ]]; then
    installPKG
else
    echo "$(date) | Unsupported package type [$packageType]"
    exit 1
fi