BCI Live Session — Setup Guide
==============================

WHAT THIS IS
  The Windows machine reads EEG from the OpenBCI headset and sends motor
  imagery predictions to the visionOS app on the Mac over Wi-Fi.
  The Mac needs nothing installed — just a WebSocket URL in the app.


WINDOWS MACHINE — DO THIS ONCE BEFORE THE SESSION
--------------------------------------------------
1. Install Python 3.9 or newer
   https://www.python.org/downloads/
   (tick "Add Python to PATH" during install)

2. Open a terminal in this folder and run:
      pip install -r requirements.txt

3. Run FIREWALL_SETUP.bat as Administrator (right-click -> Run as administrator)
   This opens port 8765 so the Mac can connect. Only needs to be done once.


WINDOWS MACHINE — ON THE DAY
-----------------------------
1. Plug in the OpenBCI Cyton dongle

2. Open OpenBCI GUI
   - Select your COM port and start the session
   - Go to: Networking -> LSL -> Start
   (This broadcasts the EEG signal so our script can read it)

3. Double-click FIND_MY_IP.bat
   Note the 192.168.x.x address — you will give this to the Mac operator.

4. Double-click START.bat
   Wait until you see:
      Continuous mode  |  thresholds left=0.6 right=0.75 both=0.45 ...
   The script is now running.


MAC / visionOS
--------------
No installation needed.

In the visionOS app, set the WebSocket server to:
   ws://192.168.x.x:8765/

Replace 192.168.x.x with the IP from FIND_MY_IP.bat on the Windows machine.

Both the Mac and Windows must be on the SAME Wi-Fi network.


HOW IT WORKS
------------
Once everything is connected:

  - Imagine "left hand"  for about 4 seconds -> LEFT  command fires
  - Imagine "right hand" for about 4 seconds -> RIGHT command fires
  - Imagine "both hands" for about 4 seconds -> BOTH  command fires

Each class has its own confidence threshold (left=60%, right=75%, both=45%).
The same class must win twice in a row above its threshold before the command
fires, so low-confidence noise is ignored. After a command fires there is a
3-second pause before the next one can trigger.

The Windows terminal will print:
  [FIRE #1] LEFT  p=0.83  -> sent to visionOS


FILES IN THIS FOLDER
--------------------
  bci_inference.py             Main inference script
  models/eeg_conformer.py      Model architecture
  models/eegnet.py             Fallback model architecture
  visionpro_sota_finetuned.pth Trained model weights
  requirements.txt             Python dependencies
  START.bat                    Launch on the day
  FIND_MY_IP.bat               Show Windows LAN IP
  FIREWALL_SETUP.bat           Open port 8765 (run once as Admin)
  PREPARE_PACKAGE.bat          Copy model file (only needed in the project)
