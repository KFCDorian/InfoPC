#!/bin/bash
# Désinstalle InfoPC complètement.
set -uo pipefail

BUNDLE_ID="com.kfcdorian.infopc"
launchctl bootout "gui/$(id -u)/${BUNDLE_ID}" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/${BUNDLE_ID}.plist"
rm -rf "$HOME/Applications/InfoPC.app"
sudo rm -f /usr/local/bin/infopc-fanctl /etc/sudoers.d/infopc
echo "✅ InfoPC désinstallé."
