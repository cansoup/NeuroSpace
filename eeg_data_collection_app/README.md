# EEG Data Collection Application

Desktop application for collecting motor imagery EEG data using OpenBCI Cyton headset.

## Overview

This application facilitates the collection of EEG data for 4-class motor imagery tasks. The system provides real-time visualization of 8-channel EEG signals, automated trial sequencing, and standardized data export formats.

## Requirements

### Hardware
- OpenBCI Cyton 8-channel EEG headset
- USB dongle for wireless communication
- Computer running Windows, macOS, or Linux

### Software Dependencies

```bash
pip install -r requirements.txt
```

Required packages:
- PyQt5 (GUI framework)
- pyqtgraph (real-time plotting)
- mne (EEG data handling)
- numpy (numerical operations)
- pyxdf (XDF file format)
- brainflow (OpenBCI interface)

## Installation

1. Clone the repository
2. Install dependencies: `pip install -r requirements.txt`
3. Verify BrainFlow installation: `pip install brainflow`

## Usage

### Starting the Application

```bash
python main.py
```

### Data Collection Workflow

1. **Hardware Setup**
   - Power on OpenBCI Cyton headset
   - Connect USB dongle to computer
   - Note the COM port (Windows Device Manager → Ports)

2. **Application Setup**
   - Click "Connect Headset" button
   - Enter subject identifier (e.g., "S001")
   - Configure trials per class (default: 3)
   - Set trial duration (default: 4 seconds)

3. **Recording Session**
   - Click "Start Recording"
   - Application presents visual cues in randomized order
   - Subject performs motor imagery tasks as indicated
   - Session runs automatically through all trials

4. **Data Export**
   - Click "Stop & Save" upon completion
   - Select output format: XDF, GDF, or both
   - Files saved to `output/` directory

## Motor Imagery Tasks

The application supports four motor imagery classes:

- **Left**: Left hand movement imagery
- **Right**: Right hand movement imagery
- **Down**: Foot movement imagery
- **Up**: Tongue movement imagery

Each trial presents visual cues with directional arrows and text instructions.

## Trial Structure

```
Ready Phase (2s) → Task Execution (4s) → Rest Period (2s) → Next Trial
```

Default configuration:
- 3 trials per class
- 4 classes total
- 12 trials per session
- Approximately 2 minutes total duration

Trials are randomized to minimize order effects.

## Event Markers

The application logs event markers with the following codes:

| Code  | Description        |
|-------|--------------------|
| 32766 | Session start      |
| 768   | Trial start        |
| 769   | Left hand cue      |
| 770   | Right hand cue     |
| 771   | Foot cue           |
| 772   | Tongue cue         |
| 782   | Trial end          |

These markers are synchronized with EEG data for offline analysis.

## Data Formats

### XDF (Extensible Data Format)
- Industry standard for multimodal recordings
- Contains two streams: EEG data and event markers
- Compatible with EEGLAB, MNE-Python, and other analysis tools
- Filename: `output/<subject_id>.xdf`

### GDF (General Data Format)
- Biosignal format used in BCI competitions
- Includes event annotations as MNE annotations
- Compatible with existing preprocessing pipeline
- Filename: `output/<subject_id>.gdf`

## Configuration

Modify `config.py` to adjust application parameters:

```python
# Hardware settings
N_CHANNELS = 8
SAMPLING_RATE = 250  # Hz

# Task parameters
TASKS = ['left', 'right', 'down', 'up']
TRIALS_PER_TASK = 3
TRIAL_DURATION = 4.0  # seconds
REST_DURATION = 2.0   # seconds

# Event marker codes
MARKERS = {
    'session_start': 32766,
    'trial_start': 768,
    'left_cue': 769,
    'right_cue': 770,
    'down_cue': 771,
    'up_cue': 772,
    'trial_end': 782
}
```

## Application Structure

```
eeg_data_collection_app/
├── main.py                  # Application entry point
├── config.py                # Configuration parameters
├── requirements.txt         # Python dependencies
├── gui/
│   ├── main_window.py       # Main application window
│   ├── eeg_plotter.py       # Real-time signal visualization
│   └── cue_display.py       # Task cue presentation
├── data/
│   ├── headset_interface.py # OpenBCI hardware interface
│   ├── event_logger.py      # Event marker management
│   └── data_saver.py        # File export functionality
└── output/                  # Data output directory
```

## Troubleshooting

### Connection Failures
- Verify headset power status
- Check USB dongle connection
- Confirm correct COM port
- Try different USB port if issues persist

### Missing Dependencies
```bash
pip install -r requirements.txt
pip install brainflow
```

### Signal Quality Issues
- Check electrode impedance
- Verify proper electrode placement
- Ensure conductive gel application
- Check wireless signal strength

### Application Errors
- Check terminal output for error messages
- Verify all dependencies installed correctly
- Ensure output directory has write permissions

## Data Collection Protocol

Standard procedure for collecting data:

1. **Preparation** (5 minutes)
   - Position EEG cap on participant
   - Verify signal quality across all channels
   - Brief participant on motor imagery tasks
   - Emphasize minimal physical movement

2. **Practice Session** (optional, 2 minutes)
   - Run single trial sequence without saving
   - Confirm participant understands task requirements

3. **Recording Session** (2 minutes)
   - Enter participant identifier
   - Start recording
   - Monitor signal quality during session
   - Avoid interruptions during active trials

4. **Verification** (1 minute)
   - Confirm successful file save
   - Check file size and format
   - Prepare for next participant

Estimated time per participant: 8-10 minutes

## Integration with ML Pipeline

Collected data can be processed using the existing BCI ML pipeline:

1. Load data using `pyxdf` or `mne` libraries
2. Apply preprocessing pipeline (`bci_ml_pipeline/scripts/1_preprocess_data.py`)
3. Train models using collected dataset
4. Evaluate performance metrics

## Technical Specifications

- **Sampling Rate**: 250 Hz
- **Channel Count**: 8 (Cyton board)
- **Data Precision**: 24-bit ADC
- **Communication**: 2.4 GHz wireless
- **Latency**: <50ms for visualization updates
- **File Size**: Approximately 2-3 MB per 2-minute session (XDF format)

## Known Limitations

- Requires physical OpenBCI hardware (no simulation mode)
- XDF export requires pyxdf library
- Windows COM port configuration may vary
- Maximum session length limited by headset battery life

## System Requirements

- **OS**: Windows 10/11, macOS 10.14+, or Linux
- **Python**: 3.8 or higher
- **RAM**: Minimum 4 GB
- **Storage**: 100 MB for application + space for data files
- **Display**: Minimum 1280x720 resolution
