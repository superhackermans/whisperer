"""
Whisperer — hold Right Cmd + Right Option to dictate.
Add Left Cmd for the large model. Add Left Option to keep punctuation.

Set WHISPERER_DEBUG=1 for verbose key-press logging.
"""

import argparse
import os
import sys

from config import load_config
from core import WhispererCore, run_hotkey_listener


def main():
    parser = argparse.ArgumentParser(description="Whisperer voice-to-text")
    parser.add_argument(
        "--log-file",
        default=None,
        help="Path to log file (default: ~/whisperer_debug.log)",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        default=None,
        help="Enable debug logging",
    )
    parser.add_argument(
        "--no-beeps",
        action="store_true",
        help="Disable audio feedback beeps",
    )
    args = parser.parse_args()

    # Determine debug early so config loading can log too
    debug = (
        args.debug
        or os.environ.get("WHISPERER_DEBUG", "").lower() in ("1", "true")
    )

    def _early_debug(msg):
        if debug:
            print(f"DEBUG {msg}", flush=True)

    _early_debug(f"[cli] Args: log_file={args.log_file}, debug={args.debug}, no_beeps={args.no_beeps}")
    _early_debug(f"[cli] WHISPERER_DEBUG={os.environ.get('WHISPERER_DEBUG', '<unset>')}")

    config = load_config(debug_log=_early_debug if debug else None)

    # CLI flags override config
    if args.log_file is not None:
        _early_debug(f"[cli] Overriding log_file: '{config.get('log_file')}' -> '{args.log_file}'")
        config["log_file"] = args.log_file
    if debug:
        config["debug"] = True
    if args.no_beeps:
        _early_debug(f"[cli] Overriding enable_beeps: {config.get('enable_beeps')} -> False")
        config["enable_beeps"] = False

    core = WhispererCore(
        whispercpp_folder=config.get("whispercpp_folder", "~/Documents/GitHub/whisper.cpp"),
        log_file=config.get("log_file", "~/whisperer_debug.log"),
        models=config.get("models"),
        prompt=config.get("prompt", "Voice dictation, clear speech, single speaker."),
        debug=config.get("debug", False),
        cleanup_recordings=config.get("cleanup_recordings", True),
        enable_beeps=config.get("enable_beeps", True),
        enable_start_sound=config.get("enable_start_sound", True),
        enable_stop_sound=config.get("enable_stop_sound", True),
        enable_error_sound=config.get("enable_error_sound", True),
        sound_volume=config.get("sound_volume", 50),
        custom_words=config.get("custom_words", {}),
    )
    core.log(f"Whisperer starting... (PID: {os.getpid()}, Python: {sys.version})")

    if not core.verify_setup():
        sys.exit(1)

    core.start()

    try:
        run_hotkey_listener(core)
    except KeyboardInterrupt:
        core.log("Exiting...")
        sys.exit(0)


if __name__ == "__main__":
    main()
