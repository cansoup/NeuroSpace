# EEG Data Collection App

Desktop application for collecting motor imagery EEG data using OpenBCI headset.

## Features

-  Real-time 8-channel EEG visualization
-  4-class motor imagery tasks (left, right, down, up)
-  Randomized trial presentation
-  Visual cues with arrows and instructions
-  Event marker logging
-  Save data in XDF or GDF format

## Installation

### 1. Install Python Dependencies

```bash
pip install -r requirements.txt
```

### 2. (Optional) Install BrainFlow for Hardware Support

```bash
pip install brainflow
```

**Note**: App will run in MOCK mode if BrainFlow is not installed. This is useful for testing the interface before connecting real hardware.

## Usage

### Quick Start

```bash
python main.py
```

### With OpenBCI Headset

1. **Connect Hardware**:
   - Power on OpenBCI Cyton headset
   - Connect via USB dongle to computer
   - Note the COM port (e.g., COM3 on Windows)

2. **Launch App**:
   ```bash
   python main.py
   ```

3. **Configure Session**:
   - Click "Connect Headset"
   - Enter Subject ID (e.g., "S001")
   - Set trials per class (default: 3)
   - Set trial duration (default: 4 seconds)

4. **Record Data**:
   - Click "Start Recording"
   - Follow on-screen cues:
     - **← LEFT**: Imagine moving left hand
     - **RIGHT →**: Imagine moving right hand
     - **↓ DOWN**: Imagine moving feet
     - **↑ UP**: Imagine moving tongue
   - App will guide through all trials automatically

5. **Save Data**:
   - Click "Stop & Save" when finished
   - Choose format: XDF, GDF, or both
   - Data saved to `output/` directory

## Trial Sequence

Each trial follows this pattern:

```
Get Ready (2s) → Task Cue (4s) → Rest (2s) → Next trial
```

**Total trials**: 12 (3 per class × 4 classes)
**Total duration**: ~2 minutes

Trials are presented in randomized order to avoid bias.

## Event Markers

Event codes logged in data files:

| Code | Event |
|------|-------|
| 32766 | Session start |
| 768 | Trial start |
| 769 | Left hand cue |
| 770 | Right hand cue |
| 771 | Foot cue (down) |
| 772 | Tongue cue (up) |
| 782 | Trial end |

## Output Files

### XDF Format
- Standard format for EEG/BCI recordings
- Contains 2 streams: EEG data + markers
- Compatible with EEGLAB, MNE, and other tools
- File: `output/<subject_id>.xdf`

### GDF Format
- General Data Format for biosignals
- Compatible with BCI Competition datasets
- Includes event annotations
- File: `output/<subject_id>.gdf`

## Testing Without Hardware

The app includes MOCK mode for development and testing:

1. Launch app normally: `python main.py`
2. Click "Connect Headset"
3. App will automatically switch to mock mode if no hardware detected
4. Mock data simulates realistic EEG signals
5. All features work identically to real mode

## Configuration

Edit `config.py` to customize:

```python
# Number of trials
TRIALS_PER_TASK = 3

# Duration settings
TRIAL_DURATION = 4.0  # seconds
REST_DURATION = 2.0   # seconds

# Tasks
TASKS = ['left', 'right', 'down', 'up']

# Event markers
MARKERS = {...}
```

## Troubleshooting

### "Failed to connect to headset"
- Check USB dongle is connected
- Verify COM port is correct
- Check headset is powered on
- Try different USB port
- App will switch to mock mode automatically

### "No module named 'brainflow'"
- Install BrainFlow: `pip install brainflow`
- Or run in mock mode (works without BrainFlow)

### "No module named 'PyQt5'"
- Install dependencies: `pip install -r requirements.txt`

### EEG plots not updating
- Check headset is streaming
- Try reconnecting headset
- Restart application

### Data file not saved
- Check output directory exists
- Verify write permissions
- Check at least one format (XDF/GDF) is selected

## Data Collection Protocol (For Class)

When collecting data from team members:

1. **Setup** (5 minutes):
   - Place EEG cap on participant
   - Check signal quality
   - Explain task to participant

2. **Practice** (optional):
   - Run one practice session without saving
   - Participant gets familiar with cues

3. **Recording** (~2 minutes):
   - Enter participant ID
   - Click "Start Recording"
   - Participant follows cues
   - Don't interrupt during recording

4. **Save and Next** (1 minute):
   - Verify data saved successfully
   - Move to next participant

**Time per participant**: ~8-10 minutes total

## File Structure

```
eeg_data_collection_app/
├── main.py                  # Application entry point
├── config.py                # Configuration
├── gui/
│   ├── main_window.py       # Main GUI window
│   ├── eeg_plotter.py       # Real-time EEG plots
│   └── cue_display.py       # Task cue display
├── data/
│   ├── headset_interface.py # OpenBCI interface
│   ├── event_logger.py      # Event marker logging
│   └── data_saver.py        # XDF/GDF saving
├── output/                  # Saved data files
├── requirements.txt
└── README.md
```

## Next Steps

After collecting data:

1. **Load data** using your existing `pyxdf` or `mne` tools
2. **Preprocess** using your pipeline (`bci_ml_pipeline/`)
3. **Train model** using collected data
4. **Test** on new subjects

## Support

For issues:
- Check this README
- Verify all dependencies installed
- Try mock mode first
- Check terminal for error messages

## Credits

Created for Team 5 - VisionStudio
Motor imagery BCI data collection for visionOS project
