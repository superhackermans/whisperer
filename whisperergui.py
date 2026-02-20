"""
Whisperer GUI — macOS menu bar app for voice dictation.

Provides a menu bar icon with model selection, keybinding configuration,
and manual start/stop. Hotkey recording also works while the app is running.
"""

from pynput import keyboard
import rumps

from config import load_config
from core import WhispererCore

KEYBINDING_OPTIONS = {
    "Cmd + Option": (keyboard.Key.cmd_r, keyboard.Key.alt_r),
    "Shift + Option": (keyboard.Key.shift, keyboard.Key.alt_r),
    "Cmd + Shift": (keyboard.Key.cmd_r, keyboard.Key.shift),
}

AVAILABLE_MODELS = ["tiny.en", "base.en", "small.en", "medium.en"]


class RecorderApp(rumps.App):
    def __init__(self):
        super().__init__("Recorder", icon="assets/mic_off.png")
        self.menu = [
            "Start Recording",
            "Stop Recording",
            "Select Model",
            "Set Keybinding",
        ]

        self.selected_model = "base.en"
        self.selected_keybinding = "Cmd + Option"
        self.cmd_key, self.option_key = KEYBINDING_OPTIONS[self.selected_keybinding]
        self.cmd_pressed = False
        self.option_pressed = False

        config = load_config()
        self.core = WhispererCore(
            whispercpp_folder=config.get("whispercpp_folder", "~/Documents/GitHub/whisper.cpp"),
            models={self.selected_model: (0, 99999999999999)},
            log_file=config.get("log_file", "~/whisperer_gui.log"),
            debug=config.get("debug", False),
            cleanup_recordings=config.get("cleanup_recordings", True),
            enable_beeps=config.get("enable_beeps", True),
            enable_start_sound=config.get("enable_start_sound", True),
            enable_stop_sound=config.get("enable_stop_sound", True),
            enable_error_sound=config.get("enable_error_sound", True),
            sound_volume=config.get("sound_volume", 50),
            on_error=self._on_error,
            on_transcribing=self._on_transcribing,
            on_transcription_done=self._on_transcription_done,
        )

    # ------------------------------------------------ callbacks from core
    def _on_error(self, title, message):
        """Show a macOS notification on error."""
        self.core.log_debug(f"[gui] Notification: title='{title}', message='{message}'")
        rumps.notification(title, "", message)

    def _on_transcribing(self):
        """Update menu bar while transcribing."""
        self.core.log_debug("[gui] State -> Transcribing...")
        self.title = "Transcribing..."

    def _on_transcription_done(self):
        """Reset menu bar after transcription."""
        self.core.log_debug("[gui] State -> Recorder (idle)")
        self.title = "Recorder"

    # ------------------------------------------------ menu actions
    @rumps.clicked("Start Recording")
    def start_recording_menu(self, _):
        self.core.log_debug("[gui] Menu: Start Recording clicked")
        if not self.core.is_recording:
            self.title = "Recording..."
            self.icon = "assets/mic_on.png"
            self.core.start_recording()
        else:
            self.core.log_debug("[gui] Already recording — ignoring menu click")

    @rumps.clicked("Stop Recording")
    def stop_recording_menu(self, _):
        self.core.log_debug("[gui] Menu: Stop Recording clicked")
        if self.core.is_recording:
            self.core.stop_recording()
            self.title = "Recorder"
            self.icon = "assets/mic_off.png"
        else:
            self.core.log_debug("[gui] Not recording — ignoring menu click")

    @rumps.clicked("Select Model")
    def select_model(self, _):
        self.core.log_debug(f"[gui] Menu: Select Model clicked (current={self.selected_model})")
        result = rumps.Window(
            title="Select Whisper Model",
            message=f"Available models: {', '.join(AVAILABLE_MODELS)}",
            default_text=self.selected_model,
        ).run()
        if result.text in AVAILABLE_MODELS:
            old = self.selected_model
            self.selected_model = result.text
            self.core.models = {self.selected_model: (0, 99999999999999)}
            self.core.log_debug(f"[gui] Model changed: {old} -> {self.selected_model}")
            rumps.alert(f"Model changed to: {self.selected_model}")
        else:
            self.core.log_debug(f"[gui] Invalid model entered: '{result.text}'")
            rumps.alert(
                f"Invalid model. Choose from: {', '.join(AVAILABLE_MODELS)}"
            )

    @rumps.clicked("Set Keybinding")
    def set_keybinding(self, _):
        self.core.log_debug(f"[gui] Menu: Set Keybinding clicked (current={self.selected_keybinding})")
        options = list(KEYBINDING_OPTIONS.keys())
        result = rumps.Window(
            title="Set Keybinding",
            message=f"Available: {', '.join(options)}",
            default_text=self.selected_keybinding,
        ).run()
        if result.text in KEYBINDING_OPTIONS:
            old = self.selected_keybinding
            self.selected_keybinding = result.text
            self.cmd_key, self.option_key = KEYBINDING_OPTIONS[result.text]
            self.core.log_debug(f"[gui] Keybinding changed: {old} -> {self.selected_keybinding}")
            rumps.alert(f"Keybinding changed to: {self.selected_keybinding}")
        else:
            self.core.log_debug(f"[gui] Invalid keybinding entered: '{result.text}'")
            rumps.alert(f"Invalid keybinding. Choose from: {', '.join(options)}")

    # ------------------------------------------------ hotkey handling
    def on_press(self, key):
        if key == self.cmd_key:
            self.cmd_pressed = True
        elif key == self.option_key:
            self.option_pressed = True

        self.core.log_debug(f"[gui-hotkey] PRESS {key}  cmd={self.cmd_pressed} opt={self.option_pressed}")

        if self.cmd_pressed and self.option_pressed and not self.core.is_recording:
            self.core.log_debug("[gui-hotkey] Trigger combo pressed — starting recording")
            self.title = "Recording..."
            self.icon = "assets/mic_on.png"
            self.core.start_recording()

    def on_release(self, key):
        if key == self.cmd_key:
            self.cmd_pressed = False
        elif key == self.option_key:
            self.option_pressed = False

        self.core.log_debug(f"[gui-hotkey] RELEASE {key}  cmd={self.cmd_pressed} opt={self.option_pressed}")

        if self.core.is_recording and (not self.cmd_pressed or not self.option_pressed):
            self.core.log_debug("[gui-hotkey] Trigger key released — stopping recording")
            self.core.stop_recording()
            self.title = "Recorder"
            self.icon = "assets/mic_off.png"

    # ------------------------------------------------ lifecycle
    def run(self):
        if not self.core.verify_setup():
            rumps.alert("Whisperer Setup Error", "whisper.cpp binary or models not found. Check your config.")
            return
        self.core.start()
        self.core.log_debug("[gui] Starting keyboard listener")
        listener = keyboard.Listener(
            on_press=self.on_press, on_release=self.on_release
        )
        listener.start()
        self.core.log_debug("[gui] Starting rumps event loop")
        super().run()


if __name__ == "__main__":
    RecorderApp().run()
