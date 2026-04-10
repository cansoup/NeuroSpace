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
        from pyxdf import write_xdf

        # Prepare EEG stream
        eeg_stream = {
            'info': {
                'name': ['OpenBCI_EEG'],
                'type': ['EEG'],
                'channel_count': [str(config.N_CHANNELS)],
                'nominal_srate': [str(config.SAMPLING_RATE)],
                'channel_format': ['float32'],
                'source_id': ['openbci_cyton'],
                'created_at': [str(eeg_timestamps[0])],
                'desc': [{
                    'channels': {
                        'channel': [
                            {'label': [f'Ch{i+1}'], 'type': ['EEG'], 'unit': ['microvolts']}
                            for i in range(config.N_CHANNELS)
                        ]
                    }
                }]
            },
            'time_series': eeg_data.T,  # XDF expects (n_samples, n_channels)
            'time_stamps': eeg_timestamps
        }

        # Prepare marker stream
        streams = [eeg_stream]

        if len(events) > 0:
            event_timestamps = np.array([e[0] for e in events])
            event_markers = np.array([[str(e[1])] for e in events], dtype=object)  # String markers

            marker_stream = {
                'info': {
                    'name': ['Markers'],
                    'type': ['Markers'],
                    'channel_count': ['1'],
                    'nominal_srate': ['0'],
                    'channel_format': ['string'],
                    'source_id': ['task_markers'],
                    'created_at': [str(event_timestamps[0])]
                },
                'time_series': event_markers,
                'time_stamps': event_timestamps
            }

            streams.append(marker_stream)

        # Save XDF file
        print(f"Saving XDF file: {filename}")
        write_xdf(filename, streams)
        print(f"  Saved successfully: {eeg_data.shape[1]} samples, {len(events)} events")

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
