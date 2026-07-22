#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#set -x

############################################################################################
##
## Script to download and set Desktop Wallpaper
##
## On macOS 14+ (Sonoma/Sequoia/Tahoe), simply replacing the image file on disk no longer
## triggers a wallpaper refresh. This script downloads the image and actively sets it as
## the desktop picture for the currently logged-in user via AppleScript.
##
## Requirements:
##   - Deploy the accompanying PPPC profile (cfg-sys-100-wallpaper-pppc.mobileconfig) via
##     Intune to pre-authorize osascript -> Finder Apple Events. Without this, a TCC
##     consent dialog will appear on the user's screen.
##   - Optionally deploy wallpaper.mobileconfig as a fallback for the override-picture-path.
##
###########################################

## Copyright (c) 2020 Microsoft Corp. All rights reserved.
## Scripts are not supported under any Microsoft standard support program or service. The scripts are provided AS IS without warranty of any kind.
## Microsoft disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a
## particular purpose. The entire risk arising out of the use or performance of the scripts and documentation remains with you. In no event shall
## Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
## (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary
## loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility
## of such damages.

# Define variables
usebingwallpaper=false # Set to true to have script fetch wallpaper from Bing
wallpaperurl="https://raw.githubusercontent.com/microsoft/intune-my-macs/main/macOS/resources/wallpaper.png"
wallpaperdir="/Users/Shared"
wallpaperfile="Wallpaper.jpg"
log="/var/log/fetchdesktopwallpaper.log"
dockMaxWait=3600  # Maximum seconds to wait for Dock (60 minutes)

# start logging

exec 1>> "$log" 2>&1

echo ""
echo "##############################################################"
echo "# $(date -u "+%Y-%m-%d %H:%M:%S UTC") | Starting download of Desktop Wallpaper"
echo "############################################################"
echo ""

##
## Wait for the Dock process to confirm we're at the user desktop.
## During Setup Assistant the Dock isn't running, and Finder Apple Events will fail.
##
dockWaited=0
while ! pgrep -x "Dock" > /dev/null 2>&1; do
    if [ "$dockWaited" -ge "$dockMaxWait" ]; then
        echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Dock not running after ${dockMaxWait}s. Likely still in Setup Assistant. Exiting."
        exit 1
    fi
    if [ "$dockWaited" -eq 0 ]; then
        echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Dock not running, waiting for user desktop..."
    fi
    sleep 5
    dockWaited=$((dockWaited + 5))
done
if [ "$dockWaited" -gt 0 ]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Dock is now running (waited ${dockWaited}s)"
else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Dock is running"
fi

##
## Checking if Wallpaper directory exists and create it if it's missing
##
if [ -d "$wallpaperdir" ]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Wallpaper dir [$wallpaperdir] already exists"
else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Creating [$wallpaperdir]"
    mkdir -p "$wallpaperdir"
fi

##
## Attempt to download the image file. No point checking if it already exists since we want to overwrite it anyway
##

if [ "$usebingwallpaper" = true ]; then

  echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Fetching today's Bing Wallpaper URL via JSON API"
  bingapiresponse=$(curl -sL "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US")
  urlbase=$(echo "$bingapiresponse" | grep -o '"urlbase":"[^"]*"' | head -1 | sed 's/"urlbase":"//;s/"//')

  if [ -n "$urlbase" ]; then
    wallpaperurl="https://www.bing.com${urlbase}_UHD.jpg"
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Setting wallpaperurl to todays Bing Desktop [$wallpaperurl]"
  else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Failed to parse Bing API response, falling back to default wallpaperurl"
  fi

fi

echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Downloading Wallpaper from [$wallpaperurl] to [$wallpaperdir/$wallpaperfile]"
curl -L -o "$wallpaperdir/$wallpaperfile" "$wallpaperurl"
if [ "$?" != "0" ]; then
   echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Failed to download wallpaper image from [$wallpaperurl]"
   exit 1
fi

echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Wallpaper [$wallpaperurl] downloaded to [$wallpaperdir/$wallpaperfile]"

##
## Verify the downloaded file is actually an image
##
filetype=$(file -b --mime-type "$wallpaperdir/$wallpaperfile")
if [[ "$filetype" != image/* ]]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Downloaded file is not an image (detected: $filetype). Aborting wallpaper set."
    exit 1
fi

##
## Set the wallpaper for the currently logged-in user
## On macOS 14+ the Dock/WallpaperKit no longer picks up file changes automatically,
## so we must actively tell Finder to update the desktop picture.
##
currentUser=$(stat -f "%Su" /dev/console)
if [ "$currentUser" = "root" ] || [ "$currentUser" = "loginwindow" ] || [ -z "$currentUser" ]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | No user currently logged in (console user: ${currentUser:-none}). Wallpaper downloaded but not applied — it will be picked up by the override-picture-path profile at next login."
    exit 0
fi

currentUserUID=$(id -u "$currentUser")
echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Setting wallpaper for user [$currentUser] (UID: $currentUserUID)"

wallpaperResult=$(/bin/launchctl asuser "$currentUserUID" sudo -u "$currentUser" /usr/bin/osascript -e "
    tell application \"Finder\"
        set desktop picture to POSIX file \"$wallpaperdir/$wallpaperfile\"
    end tell
" 2>&1)
osascriptExitCode=$?

if [ "$osascriptExitCode" = "0" ]; then
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Wallpaper successfully set for user [$currentUser]"
    exit 0
else
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Failed to set wallpaper via osascript for user [$currentUser] (exit code: $osascriptExitCode)"
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | osascript output: $wallpaperResult"
    echo "$(date -u "+%Y-%m-%d %H:%M:%S UTC") | Check that the PPPC profile (wallpaper-pppc.mobileconfig) is deployed."
    exit 1
fi
