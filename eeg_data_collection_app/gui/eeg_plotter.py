"""
Real-time EEG data plotter
"""

import sys
import os
import numpy as np
from PyQt5.QtWidgets import QWidget, QVBoxLayout
from PyQt5.QtCore import QTimer
import pyqtgraph as pg

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config

class EEGPlotter(QWidget):
    """Widget for real-time EEG visualization"""

    def __init__(self):
        super().__init__()
        self.headset = None
        self.plots = []
        self.curves = []
        self.data_buffer = np.zeros((config.N_CHANNELS, int(config.PLOT_DURATION * config.SAMPLING_RATE)))

        self.init_ui()

        # Update timer
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_plots)

    def init_ui(self):
        """Initialize plotting UI"""
        layout = QVBoxLayout()
        self.setLayout(layout)

        # Create plot widget
        self.plot_widget = pg.GraphicsLayoutWidget()
        layout.addWidget(self.plot_widget)

        # Create subplots for each channel
        for i in range(config.N_CHANNELS):
            plot = self.plot_widget.addPlot(row=i, col=0)
            plot.setLabel('left', f'Ch{i+1}', units='uV')
            plot.setYRange(-200, 200)
            plot.showGrid(x=True, y=True, alpha=0.3)

            # Hide x-axis labels except for last plot
            if i < config.N_CHANNELS - 1:
                plot.hideAxis('bottom')
            else:
                plot.setLabel('bottom', 'Time', units='s')

            curve = plot.plot(pen=pg.mkPen(color=(0, 150, 255), width=1))
            self.plots.append(plot)
            self.curves.append(curve)

    def start_plotting(self, headset):
        """Start real-time plotting"""
        self.headset = headset
        self.timer.start(config.PLOT_UPDATE_INTERVAL)

    def stop_plotting(self):
        """Stop real-time plotting"""
        # Stop the timer before detaching headset so a pending tick can't fire
        # against a torn-down board.
        self.timer.stop()
        self.headset = None

    def update_plots(self):
        """Update plots with new data"""
        if self.headset is None:
            return

        # The board can be released between this check and the read
        # (main thread vs. Qt timer). Guard against AttributeError / BrainFlow
        # errors so the GUI doesn't crash on a mid-disconnect tick.
        try:
            new_data = self.headset.get_current_data(num_samples=10)
        except (AttributeError, Exception):
            return

        if new_data is None or new_data.shape[1] == 0:
            return

        # Shift buffer and add new data
        self.data_buffer = np.roll(self.data_buffer, -new_data.shape[1], axis=1)
        self.data_buffer[:, -new_data.shape[1]:] = new_data

        # Update each channel plot
        time_axis = np.linspace(0, config.PLOT_DURATION, self.data_buffer.shape[1])

        for i in range(config.N_CHANNELS):
            self.curves[i].setData(time_axis, self.data_buffer[i, :])
