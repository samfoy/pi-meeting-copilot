#!/usr/bin/env python3
"""Meeting Transcriber — macOS menu bar app with audio source selection.

Requirements:
    pip3 install rumps

Usage:
    python3 menubar.py
"""

import os
import re
import signal
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path

import rumps


WHISPER_MODEL = os.environ.get(
    "WHISPER_MODEL", str(Path.home() / ".whisper-models/ggml-medium.en.bin")
)
TRANSCRIPT_DIR = os.environ.get("TRANSCRIPT_DIR", str(Path.home() / "transcripts"))
CLOUD_DESKTOP = os.environ.get(
    "CLOUD_DESKTOP", "dev-dsk-samfp-2a-d82872ff.us-west-2.amazon.com"
)
REMOTE_PATH = "/tmp/live-transcript.txt"
SYNC_INTERVAL = 3


def find_whisper_bin():
    """Locate the whisper-stream binary."""
    for candidate in ["whisper-stream", "/opt/homebrew/bin/whisper-stream"]:
        if candidate.startswith("/"):
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
        else:
            result = subprocess.run(
                ["which", candidate], capture_output=True, text=True
            )
            if result.returncode == 0:
                return result.stdout.strip()
    return None


def list_capture_devices():
    """Query whisper-stream for available capture devices.

    Returns list of (id, name) tuples.
    """
    whisper_bin = find_whisper_bin()
    if not whisper_bin:
        return []

    try:
        result = subprocess.run(
            [whisper_bin, "--capture", "-1", "--model", "/dev/null"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        output = result.stdout + result.stderr
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []

    devices = []
    for line in output.splitlines():
        # Match lines like: "  - Capture device #0: 'BlackHole 2ch'"
        m = re.match(r"\s*-\s*Capture device #(\d+):\s*'(.+)'", line)
        if m:
            devices.append((int(m.group(1)), m.group(2)))
    return devices


class TranscriberApp(rumps.App):
    def __init__(self):
        super().__init__("🎙️", quit_button=None)

        self.selected_device = None
        self.selected_device_name = None
        self.transcribe_proc = None
        self.sync_thread = None
        self.sync_stop = threading.Event()
        self.transcript_file = None

        # Build menu
        self.source_menu = rumps.MenuItem("Audio Source")
        self.start_item = rumps.MenuItem("Start Recording", callback=self.toggle_recording)
        self.sync_item = rumps.MenuItem("Sync to Cloud Desktop", callback=self.toggle_sync_setting)
        self.sync_item.state = True  # on by default
        self.do_sync = True
        self.status_item = rumps.MenuItem("Idle")
        self.status_item.set_callback(None)
        self.open_transcript_item = rumps.MenuItem(
            "Open Transcript Folder", callback=self.open_transcript_folder
        )
        self.quit_item = rumps.MenuItem("Quit", callback=self.quit_app)

        self.menu = [
            self.source_menu,
            None,  # separator
            self.start_item,
            self.sync_item,
            None,
            self.status_item,
            self.open_transcript_item,
            None,
            self.quit_item,
        ]

        # Populate devices on launch
        self.refresh_devices()

    def refresh_devices(self):
        """Refresh the audio source dropdown."""
        self.source_menu.clear()
        devices = list_capture_devices()

        if not devices:
            no_devices = rumps.MenuItem("No devices found")
            no_devices.set_callback(None)
            self.source_menu.add(no_devices)
            return

        for dev_id, dev_name in devices:
            item = rumps.MenuItem(
                f"{dev_name}", callback=self.select_device
            )
            item._device_id = dev_id
            item._device_name = dev_name

            # Auto-select BlackHole if present
            if "blackhole" in dev_name.lower() and self.selected_device is None:
                item.state = True
                self.selected_device = dev_id
                self.selected_device_name = dev_name

            self.source_menu.add(item)

        self.source_menu.add(None)  # separator
        self.source_menu.add(
            rumps.MenuItem("Refresh Devices", callback=lambda _: self.refresh_devices())
        )

        # If nothing auto-selected, pick the first one
        if self.selected_device is None and devices:
            first_id, first_name = devices[0]
            self.selected_device = first_id
            self.selected_device_name = first_name
            for item in self.source_menu.values():
                if hasattr(item, "_device_id") and item._device_id == first_id:
                    item.state = True
                    break

    def select_device(self, sender):
        """Handle device selection from dropdown."""
        if self.transcribe_proc is not None:
            rumps.alert(
                "Can't switch source while recording",
                "Stop the current recording first.",
            )
            return

        # Uncheck all, check selected
        for item in self.source_menu.values():
            if hasattr(item, "_device_id"):
                item.state = False
        sender.state = True
        self.selected_device = sender._device_id
        self.selected_device_name = sender._device_name

    def toggle_sync_setting(self, sender):
        self.do_sync = not self.do_sync
        sender.state = self.do_sync

    def toggle_recording(self, sender):
        if self.transcribe_proc is None:
            self.start_recording()
        else:
            self.stop_recording()

    def start_recording(self):
        whisper_bin = find_whisper_bin()
        if not whisper_bin:
            rumps.alert("whisper-stream not found", "Install with: brew install whisper-cpp")
            return

        if not os.path.isfile(WHISPER_MODEL):
            rumps.alert("Whisper model not found", f"Expected at:\n{WHISPER_MODEL}")
            return

        if self.selected_device is None:
            rumps.alert("No audio source selected", "Pick a device from Audio Source menu.")
            return

        # Create transcript file
        os.makedirs(TRANSCRIPT_DIR, exist_ok=True)
        timestamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        self.transcript_file = os.path.join(TRANSCRIPT_DIR, f"{timestamp}.txt")
        latest_link = os.path.join(TRANSCRIPT_DIR, "latest.txt")

        # Update symlink
        if os.path.islink(latest_link):
            os.unlink(latest_link)
        os.symlink(self.transcript_file, latest_link)

        Path(self.transcript_file).touch()

        # Launch whisper-stream
        cmd = [
            whisper_bin,
            "--model", WHISPER_MODEL,
            "--capture", str(self.selected_device),
            "--file", self.transcript_file,
            "--threads", "4",
            "--step", "5000",
            "--length", "10000",
            "--keep", "0",
            "--vad-thold", "0.8",
        ]

        try:
            self.transcribe_proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=os.setsid,
            )
        except Exception as e:
            rumps.alert("Failed to start transcription", str(e))
            return

        # Start sync if enabled
        if self.do_sync:
            self.sync_stop.clear()
            self.sync_thread = threading.Thread(target=self._sync_loop, daemon=True)
            self.sync_thread.start()

        # Update UI
        self.title = "🔴"
        self.start_item.title = "Stop Recording"
        self.status_item.title = f"Recording — {self.selected_device_name}"

        # Start status updater
        self._status_timer = rumps.Timer(self._update_status, 5)
        self._status_timer.start()

    def stop_recording(self):
        if self.transcribe_proc:
            try:
                os.killpg(os.getpgid(self.transcribe_proc.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                try:
                    self.transcribe_proc.kill()
                except Exception:
                    pass
            self.transcribe_proc = None

        # Stop sync
        self.sync_stop.set()
        if self.sync_thread:
            self.sync_thread.join(timeout=5)
            self.sync_thread = None

        # Final sync
        if self.do_sync and self.transcript_file and os.path.isfile(self.transcript_file):
            self._do_sync()

        # Stop status timer
        if hasattr(self, "_status_timer"):
            self._status_timer.stop()

        # Update UI
        self.title = "🎙️"
        self.start_item.title = "Start Recording"
        lines = self._line_count()
        self.status_item.title = f"Idle — last transcript: {lines} lines"

    def _sync_loop(self):
        """Background thread: sync transcript to cloud desktop."""
        while not self.sync_stop.is_set():
            self._do_sync()
            self.sync_stop.wait(SYNC_INTERVAL)

    def _do_sync(self):
        if not self.transcript_file or not os.path.isfile(self.transcript_file):
            return
        try:
            subprocess.run(
                ["scp", "-q", self.transcript_file, f"{CLOUD_DESKTOP}:{REMOTE_PATH}"],
                timeout=10,
                capture_output=True,
            )
        except Exception:
            pass

    def _line_count(self):
        if self.transcript_file and os.path.isfile(self.transcript_file):
            try:
                with open(self.transcript_file) as f:
                    return sum(1 for _ in f)
            except Exception:
                pass
        return 0

    def _update_status(self, _):
        if self.transcribe_proc is None:
            return
        # Check if process died
        if self.transcribe_proc.poll() is not None:
            self.stop_recording()
            rumps.notification(
                "Transcription stopped",
                "The whisper-stream process exited unexpectedly.",
                "",
            )
            return
        lines = self._line_count()
        self.status_item.title = f"Recording — {lines} lines — {self.selected_device_name}"

    def open_transcript_folder(self, _):
        subprocess.run(["open", TRANSCRIPT_DIR])

    def quit_app(self, _):
        self.stop_recording()
        rumps.quit_application()


if __name__ == "__main__":
    TranscriberApp().run()
