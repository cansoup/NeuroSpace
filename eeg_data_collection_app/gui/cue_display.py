"""
Task cue display widget
"""

import sys
import os
import random
from PyQt5.QtWidgets import QWidget, QVBoxLayout, QLabel
from PyQt5.QtCore import Qt, QTimer, pyqtSignal
from PyQt5.QtGui import QFont

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config

class CueDisplay(QWidget):
    """Widget for displaying task cues to the user"""

    # Signals
    trial_started = pyqtSignal(int, str)  # trial_num, task
    trial_completed = pyqtSignal(int)     # trial_num
    experiment_finished = pyqtSignal()

    def __init__(self):
        super().__init__()
        self.current_trial = 0
        self.trial_sequence = []
        self.is_paused = False
        self.timer = QTimer()
        self.timer.timeout.connect(self.next_state)

        self.state = 'idle'  # idle, ready, task, rest
        self.current_task = None

        self.init_ui()

    def init_ui(self):
        """Initialize cue display UI"""
        layout = QVBoxLayout()
        self.setLayout(layout)

        # Main cue label
        self.cue_label = QLabel("Ready to begin")
        self.cue_label.setAlignment(Qt.AlignCenter)
        self.cue_label.setFont(QFont('Arial', 48, QFont.Bold))
        self.cue_label.setStyleSheet("background-color: #ecf0f1; padding: 20px;")
        layout.addWidget(self.cue_label)

        # Trial counter label
        self.counter_label = QLabel("")
        self.counter_label.setAlignment(Qt.AlignCenter)
        self.counter_label.setFont(QFont('Arial', 16))
        layout.addWidget(self.counter_label)

    def start_experiment(self):
        """Start the experiment sequence"""
        # Generate randomized trial sequence
        self.trial_sequence = config.TASKS * config.TRIALS_PER_TASK
        random.shuffle(self.trial_sequence)

        self.current_trial = 0
        self.state = 'ready'
        self.show_ready()

        # Start timer for first ready period
        self.timer.start(int(config.READY_DURATION * 1000))

    def next_state(self):
        """Advance to next state in the trial sequence"""
        self.timer.stop()

        if self.state == 'ready':
            # Move to task cue
            if self.current_trial < len(self.trial_sequence):
                self.current_task = self.trial_sequence[self.current_trial]
                self.state = 'task'
                self.show_task_cue()
                self.trial_started.emit(self.current_trial + 1, self.current_task)
                self.timer.start(int(config.TRIAL_DURATION * 1000))
            else:
                # Experiment finished
                self.finish_experiment()

        elif self.state == 'task':
            # Move to rest
            self.state = 'rest'
            self.show_rest()
            self.current_trial += 1
            self.trial_completed.emit(self.current_trial)
            self.timer.start(int(config.REST_DURATION * 1000))

        elif self.state == 'rest':
            # Move to ready for next trial
            if self.current_trial < len(self.trial_sequence):
                self.state = 'ready'
                self.show_ready()
                self.timer.start(int(config.READY_DURATION * 1000))
            else:
                self.finish_experiment()

    def show_ready(self):
        """Display ready message"""
        self.cue_label.setText("Get Ready...")
        self.cue_label.setStyleSheet("background-color: #ecf0f1; color: #7f8c8d; padding: 20px;")
        self.update_counter()

    def show_task_cue(self):
        """Display task cue"""
        # Arrow symbols for each task
        arrows = {
            'left': '← LEFT',
            'right': 'RIGHT →',
            'down': '↓ DOWN',
            'up': '↑ UP'
        }

        instructions = {
            'left': 'Imagine moving your LEFT hand',
            'right': 'Imagine moving your RIGHT hand',
            'down': 'Imagine moving your FEET',
            'up': 'Imagine moving your TONGUE'
        }

        arrow = arrows.get(self.current_task, self.current_task.upper())
        color = config.CUE_COLORS.get(self.current_task, '#95a5a6')

        self.cue_label.setText(f"{arrow}\n\n{instructions.get(self.current_task, '')}")
        self.cue_label.setStyleSheet(f"background-color: {color}; color: white; padding: 20px;")
        self.update_counter()

    def show_rest(self):
        """Display rest message"""
        self.cue_label.setText("Rest")
        self.cue_label.setStyleSheet("background-color: #34495e; color: white; padding: 20px;")
        self.update_counter()

    def update_counter(self):
        """Update trial counter"""
        total_trials = len(self.trial_sequence)
        self.counter_label.setText(f"Trial {self.current_trial + 1} / {total_trials}")

    def finish_experiment(self):
        """Finish the experiment"""
        self.cue_label.setText("✓ Experiment Complete!")
        self.cue_label.setStyleSheet("background-color: #27ae60; color: white; padding: 20px;")
        self.counter_label.setText("All trials finished")
        self.state = 'idle'
        self.experiment_finished.emit()

    def pause(self):
        """Pause the experiment"""
        self.is_paused = True
        self.timer.stop()
        self.cue_label.setText("PAUSED")
        self.cue_label.setStyleSheet("background-color: #e67e22; color: white; padding: 20px;")

    def resume(self):
        """Resume the experiment"""
        self.is_paused = False

        # Resume from current state
        if self.state == 'ready':
            self.show_ready()
            self.timer.start(int(config.READY_DURATION * 1000))
        elif self.state == 'task':
            self.show_task_cue()
            self.timer.start(int(config.TRIAL_DURATION * 1000))
        elif self.state == 'rest':
            self.show_rest()
            self.timer.start(int(config.REST_DURATION * 1000))

    def stop(self):
        """Stop the experiment"""
        self.timer.stop()
        self.state = 'idle'

    def reset(self):
        """Reset to initial state"""
        self.cue_label.setText("Ready to begin")
        self.cue_label.setStyleSheet("background-color: #ecf0f1; padding: 20px;")
        self.counter_label.setText("")
        self.current_trial = 0
        self.trial_sequence = []
        self.state = 'idle'

    def is_running(self):
        """Check if experiment is running"""
        return not self.is_paused and self.state != 'idle'
