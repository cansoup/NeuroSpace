"""
Interface for OpenBCI headset using BrainFlow
"""

import sys
import os
import numpy as np
import time
import serial.tools.list_ports

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config

from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds
from brainflow.exit_codes import BrainFlowError

# FTDI USB vendor ID. OpenBCI Cyton dongle uses the FT231X chip in this family.
FTDI_VID = 0x0403


def scan_com_ports():
    """
    Scan for available COM ports, FTDI devices first.

    Returns:
        list: Tuples of (port_device, port_description). FTDI ports (likely
              OpenBCI dongles) are placed at the front of the list.
    """
    ftdi_ports = []
    other_ports = []
    for port in serial.tools.list_ports.comports():
        if port.vid == FTDI_VID:
            label = f"{port.device} - {port.description} [OpenBCI likely]"
            ftdi_ports.append((port.device, label))
        else:
            other_ports.append((port.device, f"{port.device} - {port.description}"))
    return ftdi_ports + other_ports


class HeadsetInterface:
    """Interface for OpenBCI Cyton headset"""

    def __init__(self):
        self.board = None
        self.board_id = None
        self.connected = False

        # Data storage
        self.all_data = []
        self.all_timestamps = []

    def connect(self, serial_port=None, board_id=None):
        """
        Connect to OpenBCI headset, or to BrainFlow's synthetic board for testing.

        Args:
            serial_port: COM port for headset (e.g., 'COM3'). Required for
                         real hardware, ignored for SYNTHETIC_BOARD.
            board_id: BrainFlow board id. Defaults to CYTON_BOARD.
                      Pass BoardIds.SYNTHETIC_BOARD to test without hardware.

        Returns:
            bool: True if connected successfully.

        Raises:
            Exception: If connection fails with detailed error message.
        """
        if board_id is None:
            board_id = BoardIds.CYTON_BOARD

        is_synthetic = board_id == BoardIds.SYNTHETIC_BOARD

        if not is_synthetic and not serial_port:
            raise ValueError(
                "Serial port must be specified.\n\n"
                "Please select a COM port from the dropdown menu.\n"
                "If no ports are listed, check:\n"
                "1. OpenBCI dongle is plugged into USB\n"
                "2. Headset is powered on\n"
                "3. Click 'Refresh Ports' to rescan"
            )

        # Remember which board we're on so data-extraction can look up channels.
        self.board_id = board_id

        params = BrainFlowInputParams()
        if not is_synthetic:
            params.serial_port = serial_port

        # prepared tracks whether we got past prepare_session() so the
        # except handler knows whether to call release_session() on cleanup.
        prepared = False
        try:
            self.board = BoardShim(board_id, params)
            self.board.prepare_session()
            prepared = True
            self.board.start_stream()
            self.connected = True
            label = "synthetic board" if is_synthetic else serial_port
            print(f"Connected to {label}")
            return True

        except Exception as e:
            # Release any half-initialized session to avoid "already prepared" on retry.
            if prepared and self.board is not None:
                try:
                    self.board.release_session()
                except Exception:
                    pass
            self.board = None
            self.connected = False
            target = "synthetic board" if is_synthetic else serial_port
            raise Exception(
                f"Failed to connect to {target}\n\n"
                f"Error: {str(e)}\n\n"
                "Troubleshooting:\n"
                "1. Try a different COM port\n"
                "2. Verify headset is powered on\n"
                "3. Check USB dongle connection\n"
                "4. Restart the application"
            )

    def disconnect(self):
        """Disconnect from headset"""
        # Flip connected first so the plotter's next tick short-circuits
        # before we start tearing down the board.
        self.connected = False

        if self.board is not None:
            try:
                self.board.stop_stream()
                self.board.release_session()
            except Exception as e:
                print(f"Error disconnecting: {e}")

        self.board = None
        self.board_id = None

    def is_connected(self):
        """Check if headset is connected"""
        return self.connected

    def get_current_data(self, num_samples=10):
        """
        Get most recent data samples.

        Returns None if the board has been released between the caller's
        connectivity check and this call (e.g. user clicked Disconnect while
        the plotter timer was mid-tick).

        Args:
            num_samples: Number of samples to retrieve

        Returns:
            np.ndarray of shape (n_channels, num_samples), or None if not streaming.
        """
        if not self.connected or self.board is None or self.board_id is None:
            return None

        try:
            data = self.board.get_current_board_data(num_samples)
            eeg_channels = BoardShim.get_eeg_channels(self.board_id.value)
        except BrainFlowError:
            return None

        # Synthetic board exposes 16 EEG channels; clip to the count the app
        # is configured for (Cyton = 8) so the plot buffer shape matches.
        eeg_channels = eeg_channels[:config.N_CHANNELS]
        data = data[eeg_channels, :]

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
