@echo off
REM Run this ONCE from inside the project to copy the model checkpoint.
REM After running this, the windows_deploy folder is ready to zip and transfer.

cd /d "%~dp0"
echo Copying model checkpoint...
copy "..\visionpro_sota_finetuned.pth" "visionpro_sota_finetuned.pth"
if exist "visionpro_sota_finetuned.pth" (
    echo Done. visionpro_sota_finetuned.pth is now in this folder.
    echo You can now zip the entire windows_deploy folder and transfer it.
) else (
    echo ERROR: Copy failed. Make sure visionpro_sota_finetuned.pth exists in the project root.
)
pause
