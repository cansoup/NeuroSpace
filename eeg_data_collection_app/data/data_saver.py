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
    Save data in XDF format using pylsl

    Args:
        filename (str): Output filename
        eeg_data (np.ndarray): EEG data of shape (n_channels, n_samples)
        eeg_timestamps (np.ndarray): Timestamps for each sample
        events (list): List of (timestamp, marker, description) tuples
    """
    try:
        import xml.etree.ElementTree as ET
        import struct
        import gzip

        print(f"Saving XDF file: {filename}")

        # Create XDF file structure
        with gzip.open(filename, 'wb') as f:
            # Write XDF header
            f.write(b'XDF:')

            # Write EEG stream header
            eeg_header = f'''<?xml version="1.0"?>
<info>
  <name>OpenBCI_EEG</name>
  <type>EEG</type>
  <channel_count>{config.N_CHANNELS}</channel_count>
  <nominal_srate>{config.SAMPLING_RATE}</nominal_srate>
  <channel_format>float32</channel_format>
  <source_id>openbci_cyton</source_id>
  <desc>
    <channels>'''

            for i in range(config.N_CHANNELS):
                eeg_header += f'''
      <channel>
        <label>Ch{i+1}</label>
        <type>EEG</type>
        <unit>microvolts</unit>
      </channel>'''

            eeg_header += '''
    </channels>
  </desc>
</info>'''

            # Write stream header chunk (chunk tag 2)
            header_bytes = eeg_header.encode('utf-8')
            f.write(struct.pack('<H', 2))  # Chunk tag
            f.write(struct.pack('<I', len(header_bytes)))  # Length
            f.write(header_bytes)

            # Write EEG samples (chunk tag 3 for samples)
            if eeg_data.shape[1] > 0:
                for i in range(eeg_data.shape[1]):
                    f.write(struct.pack('<H', 3))  # Sample chunk
                    sample_size = config.N_CHANNELS * 4 + 8  # 4 bytes per float32 + 8 for timestamp
                    f.write(struct.pack('<I', sample_size))
                    f.write(struct.pack('<d', eeg_timestamps[i]))  # Timestamp
                    for ch in range(config.N_CHANNELS):
                        f.write(struct.pack('<f', eeg_data[ch, i]))  # Sample data

            # Write marker stream if events exist
            if len(events) > 0:
                # Marker stream header
                marker_header = '''<?xml version="1.0"?>
<info>
  <name>Markers</name>
  <type>Markers</type>
  <channel_count>1</channel_count>
  <nominal_srate>0</nominal_srate>
  <channel_format>string</channel_format>
  <source_id>task_markers</source_id>
</info>'''

                header_bytes = marker_header.encode('utf-8')
                f.write(struct.pack('<H', 2))  # Chunk tag
                f.write(struct.pack('<I', len(header_bytes)))
                f.write(header_bytes)

                # Write marker samples
                for timestamp, marker, desc in events:
                    marker_str = str(marker)
                    marker_bytes = marker_str.encode('utf-8')
                    f.write(struct.pack('<H', 3))  # Sample chunk
                    sample_size = len(marker_bytes) + 1 + 8  # String + null terminator + timestamp
                    f.write(struct.pack('<I', sample_size))
                    f.write(struct.pack('<d', timestamp))  # Timestamp
                    f.write(marker_bytes)
                    f.write(b'\0')  # Null terminator

            # Write footer (chunk tag 6)
            f.write(struct.pack('<H', 6))
            f.write(struct.pack('<I', 0))

        print(f"  Saved successfully: {eeg_data.shape[1]} samples, {len(events)} events")
        return True

    except Exception as e:
        print(f"Error saving XDF: {e}")
        import traceback
        traceback.print_exc()
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
