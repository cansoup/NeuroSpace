"""
Event marker logger for recording task events
"""

import time
import numpy as np
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config

class EventLogger:
    """Logs events and markers during recording"""

    def __init__(self):
        self.events = []  # List of (timestamp, marker, description)
        self.session_start_time = None

    def start_session(self):
        """Start a new recording session"""
        self.session_start_time = time.time()
        self.add_event(config.MARKERS['session_start'], 'Session Start')

    def add_event(self, marker, description=''):
        """
        Add an event marker

        Args:
            marker (int): Marker code (e.g., 769 for left cue)
            description (str): Human-readable description
        """
        timestamp = time.time()
        self.events.append((timestamp, marker, description))
        print(f"Event logged: {marker} ({description}) at {timestamp:.2f}s")

    def get_events(self):
        """
        Get all logged events

        Returns:
            list: List of (timestamp, marker, description) tuples
        """
        return self.events

    def get_events_array(self):
        """
        Get events as numpy arrays

        Returns:
            tuple: (timestamps, markers)
        """
        if len(self.events) == 0:
            return np.array([]), np.array([])

        timestamps = np.array([event[0] for event in self.events])
        markers = np.array([event[1] for event in self.events])

        return timestamps, markers

    def reset(self):
        """Reset event logger"""
        self.events = []
        self.session_start_time = None
