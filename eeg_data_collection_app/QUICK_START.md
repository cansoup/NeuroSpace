# Quick Start Guide - EEG Data Collection App

## For Stanley and Team Members

This is a 5-minute guide to get started collecting EEG data in class.

---

## 📦 Installation (Do This Before Class)

```bash
# 1. Navigate to app directory
cd eeg_data_collection_app

# 2. Install required packages
pip install -r requirements.txt

# 3. Test the app (mock mode)
python main.py
```

**Expected result**: Window opens showing 8 EEG channels with random data

---

## 🎯 In-Class Data Collection (2 minutes per person)

### Step 1: Launch App
```bash
python main.py
```

### Step 2: Connect Headset
1. Click **"Connect Headset"** button
2. If headset found → Status shows "Connected" (green)
3. If not found → Status shows "Mock Mode" (orange) - still usable for testing!

### Step 3: Configure
- **Subject ID**: Enter participant name/ID (e.g., "S001", "soheil", etc.)
- **Trials/Class**: Leave at 3 (default)
- **Duration**: Leave at 4 seconds (default)

### Step 4: Record
1. Click **"Start Recording"**
2. Participant follows on-screen cues:
   - **← LEFT**: Imagine moving LEFT HAND
   - **RIGHT →**: Imagine moving RIGHT HAND
   - **↓ DOWN**: Imagine moving FEET
   - **↑ UP**: Imagine moving TONGUE
3. App runs through 12 trials automatically (~2 minutes)
4. When finished, click **"Stop & Save"**

### Step 5: Save
- ✅ Check **XDF** (recommended)
- ⬜ Check **GDF** (optional, for compatibility)
- Data saves to `output/` folder
- File name: `<subject_id>.xdf`

---

## 💡 Tips

### For Participants
- **Sit still** during recording
- **Close eyes** helps with imagery
- **Don't worry** about doing it "right" - just try your best
- Each cue lasts **4 seconds** - that's enough time

### For Operator (Stanley)
- **Keep laptop plugged in** - don't run on battery
- **Close other apps** - free up CPU for smooth recording
- **Test first** with mock mode before attaching headset
- **Name files clearly** - use participant initials or IDs

---

## 🔧 Troubleshooting

### "App won't start"
```bash
# Missing dependencies
pip install PyQt5 pyqtgraph numpy mne pyxdf
```

### "No headset detected"
- Check USB dongle plugged in
- Check headset powered on
- **Don't worry** - app works in MOCK mode for testing

### "Plots not moving"
- Reconnect headset (click Disconnect, then Connect)
- Restart app
- Use mock mode instead

### "Can't save file"
- Check `output/` folder exists
- Check at least one format (XDF/GDF) is checked
- Check subject ID is filled in

---

## 📊 After Collection

Your data files will be in:
```
eeg_data_collection_app/output/
├── S001.xdf
├── S002.xdf
└── ...
```

Each file contains:
- **8 channels** of EEG data (250 Hz)
- **Event markers** (when each task happened)
- **Duration**: ~2 minutes per file

---

## 🚀 Next Steps

1. **Collect data** from 3-5 team members
2. **Copy files** to USB drive or cloud
3. **Analyze later** using your existing pipeline:
   ```python
   import pyxdf
   streams, header = pyxdf.load_xdf('output/S001.xdf')
   # Your analysis code here...
   ```

---

## ⏱️ Time Budget

- Setup laptop: **5 minutes** (one time)
- Per participant:
  - Put on headset: **2 minutes**
  - Record data: **2 minutes**
  - Save and next: **1 minute**
  - **Total: ~5 minutes per person**

For 5 people: **~30 minutes total**

---

## 📞 Emergency Contacts

If something goes wrong in class:
1. Try MOCK mode (works without hardware)
2. Restart the app
3. Skip that person, come back later
4. At minimum, get 1-2 good recordings

---

**Ready to collect data!** 🎉
