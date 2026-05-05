@echo off
cd /d "%~dp0"
echo.
echo ============================================================
echo  BCI Live Session
echo ============================================================
echo.
echo Your IP address (give this to the Mac operator):
ipconfig | findstr /i "IPv4"
echo.
echo Make sure OpenBCI GUI is running with LSL output enabled before continuing.
echo (OpenBCI GUI -^> Networking -^> LSL -^> Start)
echo.
echo Press any key to start inference...
pause > nul
echo.
python bci_inference.py --continuous --bridge
pause
