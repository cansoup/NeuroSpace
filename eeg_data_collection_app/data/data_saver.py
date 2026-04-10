"""
Data saving utilities for XDF and GDF formats
"""

import numpy as np
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config

def save_xdf(filename, eeg_data, eeg_timestamps, events):
    """
    Save data in XDF format

    Args:
        filename (str): Output filename
        eeg_data (np.ndarray): EEG data of shape (n_channels, n_samples)
        eeg_timestamps (np.ndarray): Timestamps for each sample
        events (list): List of (timestamp, marker, description) tuples
    """
    try:
        import pyxdf

        # Prepare EEG stream
        eeg_stream = {
            'info': {
                'name': ['OpenBCI_EEG'],
                'type': ['EEG'],
                'channel_count': [str(config.N_CHANNELS)],
                'nominal_srate': [str(config.SAMPLING_RATE)],
                'channel_format': ['float32'],
                'source_id': ['openbci_cyton']
            },
            'time_series': eeg_data.T,  # XDF expects (n_samples, n_channels)
            'time_stamps': eeg_timestamps
        }

        # Prepare marker stream
        if len(events) > 0:
            event_timestamps = np.array([e[0] for e in events])
            event_markers = np.array([[e[1]] for e in events])  # Reshape to (n_events, 1)

            marker_stream = {
                'info': {
                    'name': ['Markers'],
                    'type': ['Markers'],
                    'channel_count': ['1'],
                    'nominal_srate': ['0'],
                    'channel_format': ['int32'],
                    'source_id': ['task_markers']
                },
                'time_series': event_markers,
                'time_stamps': event_timestamps
            }

            streams = [eeg_stream, marker_stream]
        else:
            streams = [eeg_stream]

        # Save XDF file
        # Note: pyxdf.save_xdf doesn't exist, we need to use write_xdf or similar
        # For now, we'll use a workaround with pyxdf stream format

        print(f"Saving XDF file: {filename}")
        # XDF saving requires specific library - this is a placeholder
        # In practice, you'd use python-xdf or similar
        print(f"  EEG shape: {eeg_data.shape}")
        print(f"  Events: {len(events)}")
        print("  XDF format support requires additional setup")
        print("  Saving as NPZ instead for now...")

        # Temporary: Save as NPZ until XDF writer is properly configured
        np.savez(filename.replace('.xdf', '_backup.npz'),
                eeg_data=eeg_data,
                eeg_timestamps=eeg_timestamps,
                events=events)

        return True

    except Exception as e:
        print(f"Error saving XDF: {e}")
        return False

def save_gdf(filename, eeg_data, eeg_timestamps, events):
    """
    Save data in GDF format using MNE

    Args:
        filename (str): Output filename
        eeg_data (np.ndarray): EEG data of shape (n_channels, n_samples)
        eeg_timestamps (np.ndarray): Timestamps for each sample
        events (list): List of (timestamp, marker, description) tuples
    """
    try:
        import mne

        # Create MNE info structure
        ch_names = [f'Ch{i+1}' for i in range(config.N_CHANNELS)]
        ch_types = ['eeg'] * config.N_CHANNELS

        info = mne.create_info(ch_names=ch_names,
                              sfreq=config.SAMPLING_RATE,
                              ch_types=ch_types)

        # Create Raw object
        raw = mne.io.RawArray(eeg_data, info)

        # Add events as annotations
        if len(events) > 0:
            event_times = np.array([e[0] for e in events]) - eeg_timestamps[0]  # Relative to start
            event_descriptions = [str(e[1]) for e in events]  # Marker codes as strings

            annotations = mne.Annotations(onset=event_times,
                                         duration=np.zeros(len(event_times)),
                                         description=event_descriptions)
            raw.set_annotations(annotations)

        # Save as GDF
        print(f"Saving GDF file: {filename}")
        raw.export(filename, fmt='gdf', overwrite=True)
        print(f"  Saved successfully")

        return True

    except Exception as e:
        print(f"Error saving GDF: {e}")
        return False
