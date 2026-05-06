@echo off
REM Run this ONCE as Administrator to allow visionOS to reach the WebSocket server.
REM Right-click this file -> "Run as administrator"

echo Adding firewall rule to allow incoming connections on port 8765...
netsh advfirewall firewall add rule ^
    name="BCI WebSocket Bridge" ^
    dir=in ^
    action=allow ^
    protocol=TCP ^
    localport=8765

if %errorlevel% == 0 (
    echo Done. Port 8765 is now open for incoming connections.
) else (
    echo ERROR: Failed to add rule. Did you run this as Administrator?
    echo Right-click FIREWALL_SETUP.bat and choose "Run as administrator".
)
pause
