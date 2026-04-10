"""
Interface for OpenBCI headset using BrainFlow
"""

import sys
import os
import numpy as np
import time

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config

from brainflow import BoardShim, BrainFlowInputParams, BoardIds

class HeadsetInterface:
    """Interface for OpenBCI Cyton headset"""

    def __init__(self):
        self.board = None
        self.connected = False

        # Data storage
        self.all_data = []
        self.all_timestamps = []

    def connect(self, serial_port=None):
        """
        Connect to OpenBCI headset

        Args:
            serial_port: COM port for headset (e.g., 'COM3')

        Returns:
            bool: True if connected successfully, False otherwise

        Raises:
            Exception: If connection fails
        """
        # Setup BrainFlow parameters
        params = BrainFlowInputParams()

        if serial_port:
            params.serial_port = serial_port

        # Initialize board (OpenBCI Cyton = 8 channels)
        self.board = BoardShim(BoardIds.CYTON_BOARD, params)

        # Prepare session
        self.board.prepare_session()

        # Start streaming
        self.board.start_stream()

        self.connected = True
        print(f"Connected to OpenBCI headset on {serial_port if serial_port else 'auto-detected port'}")
        return True

    def disconnect(self):
        """Disconnect from headset"""
        if self.board is not None:
            try:
                self.board.stop_stream()
                self.board.release_session()
            except Exception as e:
                print(f"Error disconnecting: {e}")

        self.connected = False
        self.board = None

    def is_connected(self):
        """Check if headset is connected"""
        return self.connected

    def get_current_data(self, num_samples=10):
        """
        Get most recent data samples

        Args:
            num_samples: Number of samples to retrieve

        Returns:
            np.ndarray: Shape (n_channels, num_samples)
        """
        if not self.connected:
            return None

        # Get real data from BrainFlow
        data = self.board.get_current_board_data(num_samples)
        # Extract EEG channels (first 8 channels for Cyton)
        eeg_channels = self.board.get_eeg_channels(BoardIds.CYTON_BOARD)
        data = data[eeg_channels, :]

        # Store data
        if data.shape[1] > 0:
            self.all_data.append(data)
            self.all_timestamps.append(time.time())

        return data

    def get_all_data(self):
        """
        Get all collected data

        Returns:
            tuple: (data, timestamps)
                data: np.ndarray of shape (n_channels, total_samples)
                timestamps: np.ndarray of timestamps
        """
        if len(self.all_data) == 0:
            return np.array([]), np.array([])

        # Concatenate all data
        all_data_concat = np.concatenate(self.all_data, axis=1)

        # Generate timestamps for each sample
        total_samples = all_data_concat.shape[1]
        timestamps = np.linspace(self.all_timestamps[0],
                                self.all_timestamps[-1],
                                total_samples)

        return all_data_concat, timestamps
