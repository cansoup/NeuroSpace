"""
Main application window for EEG data collection
"""

import sys
import os
from PyQt5.QtWidgets import (QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                             QPushButton, QLabel, QLineEdit, QComboBox,
                             QSpinBox, QCheckBox, QGroupBox, QFileDialog,
                             QProgressBar, QMessageBox)
from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtGui import QFont

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import config
from gui.eeg_plotter import EEGPlotter
from gui.cue_display import CueDisplay
from data.headset_interface import HeadsetInterface, scan_com_ports
from data.event_logger import EventLogger
from brainflow.board_shim import BoardIds

class MainWindow(QMainWindow):
    """Main application window"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle(config.WINDOW_TITLE)
        self.setGeometry(100, 100, config.WINDOW_WIDTH, config.WINDOW_HEIGHT)

        # Initialize components
        self.headset = HeadsetInterface()
        self.event_logger = EventLogger()
        self.is_recording = False

        # Setup UI
        self.init_ui()

    def init_ui(self):
        """Initialize user interface"""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        main_layout = QVBoxLayout()
        central_widget.setLayout(main_layout)

        # Top panel: Connection and settings
        main_layout.addWidget(self.create_top_panel())

        # Middle: EEG plots
        self.eeg_plotter = EEGPlotter()
        main_layout.addWidget(self.eeg_plotter, stretch=2)

        # Cue display
        self.cue_display = CueDisplay()
        main_layout.addWidget(self.cue_display, stretch=1)

        # Progress bar
        self.progress_bar = QProgressBar()
        self.progress_bar.setMaximum(config.TRIALS_PER_TASK * len(config.TASKS))
        main_layout.addWidget(self.progress_bar)

        # Bottom panel: Controls and save options
        main_layout.addWidget(self.create_bottom_panel())

    def create_top_panel(self):
        """Create top configuration panel"""
        panel = QGroupBox("Configuration")
        layout = QHBoxLayout()

        # Connection status
        self.connection_label = QLabel("Not Connected")
        self.connection_label.setStyleSheet("color: red;")
        layout.addWidget(QLabel("Status:"))
        layout.addWidget(self.connection_label)

        layout.addSpacing(10)

        # COM Port selector
        layout.addWidget(QLabel("COM Port:"))
        self.com_port_combo = QComboBox()
        self.com_port_combo.setMinimumWidth(150)
        self.refresh_com_ports()
        layout.addWidget(self.com_port_combo)

        # Refresh ports button
        refresh_btn = QPushButton("Refresh Ports")
        refresh_btn.clicked.connect(self.refresh_com_ports)
        refresh_btn.setMaximumWidth(100)
        layout.addWidget(refresh_btn)

        layout.addSpacing(10)

        # Test mode: uses BrainFlow synthetic board, ignores COM port.
        self.test_mode_check = QCheckBox("Test mode (no dongle)")
        self.test_mode_check.setToolTip(
            "Use BrainFlow's synthetic board to exercise the app without hardware."
        )
        layout.addWidget(self.test_mode_check)

        # Connect button
        self.connect_btn = QPushButton("Connect Headset")
        self.connect_btn.clicked.connect(self.toggle_connection)
        layout.addWidget(self.connect_btn)

        layout.addSpacing(20)

        # Subject ID
        layout.addWidget(QLabel("Subject ID:"))
        self.subject_input = QLineEdit()
        self.subject_input.setPlaceholderText("e.g., S001")
        self.subject_input.setMaximumWidth(100)
        layout.addWidget(self.subject_input)

        layout.addSpacing(20)

        # Trials per class
        layout.addWidget(QLabel("Trials/Class:"))
        self.trials_spin = QSpinBox()
        self.trials_spin.setMinimum(1)
        self.trials_spin.setMaximum(10)
        self.trials_spin.setValue(config.TRIALS_PER_TASK)
        self.trials_spin.setMaximumWidth(60)
        layout.addWidget(self.trials_spin)

        layout.addSpacing(20)

        # Trial duration
        layout.addWidget(QLabel("Duration (s):"))
        self.duration_spin = QSpinBox()
        self.duration_spin.setMinimum(1)
        self.duration_spin.setMaximum(10)
        self.duration_spin.setValue(int(config.TRIAL_DURATION))
        self.duration_spin.setMaximumWidth(60)
        layout.addWidget(self.duration_spin)

        layout.addStretch()

        panel.setLayout(layout)
        return panel

    def create_bottom_panel(self):
        """Create bottom control panel"""
        panel = QGroupBox("Controls")
        layout = QHBoxLayout()

        # Control buttons
        self.start_btn = QPushButton("Start Recording")
        self.start_btn.clicked.connect(self.start_recording)
        self.start_btn.setStyleSheet("background-color: #27ae60; color: white; font-weight: bold;")
        layout.addWidget(self.start_btn)

        self.pause_btn = QPushButton("Pause")
        self.pause_btn.clicked.connect(self.pause_recording)
        self.pause_btn.setEnabled(False)
        layout.addWidget(self.pause_btn)

        self.stop_btn = QPushButton("Stop & Save")
        self.stop_btn.clicked.connect(self.stop_recording)
        self.stop_btn.setEnabled(False)
        self.stop_btn.setStyleSheet("background-color: #c0392b; color: white; font-weight: bold;")
        layout.addWidget(self.stop_btn)

        layout.addSpacing(30)

        # Save format options
        layout.addWidget(QLabel("Save Format:"))
        self.xdf_check = QCheckBox("XDF")
        self.xdf_check.setChecked(True)
        layout.addWidget(self.xdf_check)

        self.gdf_check = QCheckBox("GDF")
        self.gdf_check.setChecked(False)
        layout.addWidget(self.gdf_check)

        layout.addSpacing(10)

        # Output directory
        layout.addWidget(QLabel("Directory:"))
        self.output_dir_input = QLineEdit()
        self.output_dir_input.setText(config.DEFAULT_OUTPUT_DIR)
        self.output_dir_input.setMaximumWidth(200)
        layout.addWidget(self.output_dir_input)

        browse_btn = QPushButton("Browse...")
        browse_btn.clicked.connect(self.browse_output_dir)
        layout.addWidget(browse_btn)

        layout.addStretch()

        panel.setLayout(layout)
        return panel

    def refresh_com_ports(self):
        """Refresh the list of available COM ports"""
        self.com_port_combo.clear()

        ports = scan_com_ports()

        if ports:
            for port_name, port_desc in ports:
                self.com_port_combo.addItem(port_desc, port_name)
        else:
            self.com_port_combo.addItem("No ports found", None)

    def toggle_connection(self):
        """Toggle headset connection"""
        if not self.headset.is_connected():
            test_mode = self.test_mode_check.isChecked()
            selected_port = self.com_port_combo.currentData()

            if not test_mode and not selected_port:
                QMessageBox.warning(self, "No Port Selected",
                                   "No COM port selected or available.\n\n"
                                   "Please:\n"
                                   "1. Connect OpenBCI USB dongle\n"
                                   "2. Click 'Refresh Ports'\n"
                                   "3. Select the correct COM port\n"
                                   "4. Click 'Connect Headset'\n\n"
                                   "Or tick 'Test mode (no dongle)' to use the synthetic board.")
                return

            try:
                if test_mode:
                    success = self.headset.connect(board_id=BoardIds.SYNTHETIC_BOARD)
                    status = "Connected (synthetic)"
                else:
                    success = self.headset.connect(serial_port=selected_port)
                    status = f"Connected ({selected_port})"

                if success:
                    self.connection_label.setText(status)
                    self.connection_label.setStyleSheet("color: green; font-weight: bold;")
                    self.connect_btn.setText("Disconnect")
                    self.start_btn.setEnabled(True)
                    self.com_port_combo.setEnabled(False)
                    self.test_mode_check.setEnabled(False)
                    self.eeg_plotter.start_plotting(self.headset)
            except Exception as e:
                QMessageBox.critical(self, "Connection Error", str(e))
                self.connection_label.setText("Not Connected")
                self.connection_label.setStyleSheet("color: red; font-weight: bold;")
        else:
            # Stop the plotter first so its timer can't tick against a torn-down board.
            self.eeg_plotter.stop_plotting()
            self.headset.disconnect()
            self.connection_label.setText("Not Connected")
            self.connection_label.setStyleSheet("color: red;")
            self.connect_btn.setText("Connect Headset")
            self.start_btn.setEnabled(False)
            self.com_port_combo.setEnabled(True)
            self.test_mode_check.setEnabled(True)

    def start_recording(self):
        """Start recording session"""
        # Validate subject ID
        if not self.subject_input.text().strip():
            QMessageBox.warning(self, "Input Error", "Please enter a Subject ID")
            return

        # Check at least one format is selected
        if not self.xdf_check.isChecked() and not self.gdf_check.isChecked():
            QMessageBox.warning(self, "Format Error", "Please select at least one save format")
            return

        self.is_recording = True
        self.start_btn.setEnabled(False)
        self.pause_btn.setEnabled(True)
        self.stop_btn.setEnabled(True)

        # Update configuration
        config.TRIALS_PER_TASK = self.trials_spin.value()
        config.TRIAL_DURATION = float(self.duration_spin.value())

        # Start the experiment
        self.event_logger.start_session()
        self.cue_display.start_experiment()
        self.progress_bar.setValue(0)

        # Connect cue display signals
        self.cue_display.trial_started.connect(self.on_trial_start)
        self.cue_display.trial_completed.connect(self.on_trial_complete)
        self.cue_display.experiment_finished.connect(self.on_experiment_finish)

    def pause_recording(self):
        """Pause/resume recording"""
        if self.cue_display.is_running():
            self.cue_display.pause()
            self.pause_btn.setText("Resume")
        else:
            self.cue_display.resume()
            self.pause_btn.setText("Pause")

    def stop_recording(self):
        """Stop recording and save data"""
        self.cue_display.stop()
        self.save_data()
        self.reset_ui()

    def on_trial_start(self, trial_num, task):
        """Handle trial start event"""
        marker = config.MARKERS[f'{task}_cue']
        self.event_logger.add_event(marker, task)

    def on_trial_complete(self, trial_num):
        """Handle trial completion"""
        self.progress_bar.setValue(trial_num)

    def on_experiment_finish(self):
        """Handle experiment completion"""
        QMessageBox.information(self, "Complete",
                               "Experiment finished!\nSaving data...")
        self.stop_recording()

    def save_data(self):
        """Save collected data"""
        subject_id = self.subject_input.text().strip()
        output_dir = self.output_dir_input.text()

        # Create output directory if it doesn't exist
        os.makedirs(output_dir, exist_ok=True)

        # Get data from headset
        eeg_data, timestamps = self.headset.get_all_data()
        events = self.event_logger.get_events()

        # Save in selected formats
        saved_files = []

        if self.xdf_check.isChecked():
            from data.data_saver import save_xdf
            xdf_file = os.path.join(output_dir, f"{subject_id}.xdf")
            save_xdf(xdf_file, eeg_data, timestamps, events)
            saved_files.append(xdf_file)

        if self.gdf_check.isChecked():
            from data.data_saver import save_gdf
            gdf_file = os.path.join(output_dir, f"{subject_id}.gdf")
            save_gdf(gdf_file, eeg_data, timestamps, events)
            saved_files.append(gdf_file)

        msg = "Data saved successfully:\n" + "\n".join(saved_files)
        QMessageBox.information(self, "Saved", msg)

    def browse_output_dir(self):
        """Browse for output directory"""
        directory = QFileDialog.getExistingDirectory(self, "Select Output Directory")
        if directory:
            self.output_dir_input.setText(directory)

    def reset_ui(self):
        """Reset UI to initial state"""
        self.is_recording = False
        self.start_btn.setEnabled(True)
        self.pause_btn.setEnabled(False)
        self.pause_btn.setText("Pause")
        self.stop_btn.setEnabled(False)
        self.progress_bar.setValue(0)
        self.cue_display.reset()
        self.event_logger.reset()

    def closeEvent(self, event):
        """Handle window close event"""
        if self.is_recording:
            reply = QMessageBox.question(self, 'Confirm Exit',
                                        "Recording in progress. Are you sure you want to exit?",
                                        QMessageBox.Yes | QMessageBox.No)
            if reply == QMessageBox.No:
                event.ignore()
                return

        # Clean up
        if self.headset.is_connected():
            self.headset.disconnect()
        self.eeg_plotter.stop_plotting()
        event.accept()
