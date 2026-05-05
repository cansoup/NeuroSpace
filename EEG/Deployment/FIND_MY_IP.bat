@echo off
echo.
echo Your LAN IP address (give this to the Mac operator):
echo The visionOS app should connect to:  ws://IP_BELOW:8765/
echo.
ipconfig | findstr /i "IPv4"
echo.
pause
