#!/bin/bash
# open-xcode.sh
# Opens Xcode with proper environment for FoundationDB C library

# Set environment variables for GUI apps (Xcode)
launchctl setenv PKG_CONFIG_PATH "/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
launchctl setenv PATH "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "Environment variables set for GUI apps."
echo "If Xcode was already running, please restart it."
echo ""
echo "Opening Xcode..."

open -a Xcode .
