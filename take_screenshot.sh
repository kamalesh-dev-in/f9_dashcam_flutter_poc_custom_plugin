#!/bin/bash
timestamp=$(date +"%Y%m%d_%H%M%S")
adb exec-out screencap -p > screenshots/screenshot_${timestamp}.png
echo "Screenshot saved to screenshots/screenshot_${timestamp}.png"
