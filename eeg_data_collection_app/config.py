"""
Configuration file for EEG Data Collection App
"""

# Hardware Configuration
BOARD_TYPE = "CYTON"  # OpenBCI Cyton 8-channel
N_CHANNELS = 8
SAMPLING_RATE = 250  # Hz

# Task Configuration
TASKS = ['left', 'right', 'down', 'up']
TRIALS_PER_TASK = 3
TRIAL_DURATION = 4.0  # seconds
REST_DURATION = 2.0   # seconds
READY_DURATION = 2.0  # seconds

# Event Markers (matching your XDF example format)
MARKERS = {
    'session_start': 32766,
    'trial_start': 768,
    'left_cue': 769,
    'right_cue': 770,
    'down_cue': 771,
    'up_cue': 772,
    'trial_end': 782
}

# GUI Configuration
WINDOW_TITLE = "EEG Data Collection App"
WINDOW_WIDTH = 1200
WINDOW_HEIGHT = 800

# Plot Configuration
PLOT_DURATION = 5.0  # seconds of data to display
PLOT_UPDATE_INTERVAL = 50  # ms

# Output Configuration
DEFAULT_OUTPUT_DIR = "output"
SUPPORTED_FORMATS = ['XDF', 'GDF', 'BOTH']

# Colors for cues
CUE_COLORS = {
    'left': '#3498db',    # Blue
    'right': '#e74c3c',   # Red
    'down': '#2ecc71',    # Green
    'up': '#f39c12'       # Orange
}
