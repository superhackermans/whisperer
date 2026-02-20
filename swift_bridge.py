"""
Bridge between the Swift menu bar app and WhispererCore.

Reads commands from stdin, streams status to stdout via core.log().
Does NOT modify any existing Python files.

Commands (one per line):
  start                    Start recording (auto model)
  start --large            Start recording with large model
  start --punct            Start recording, keep punctuation
  start --large --punct    Both
  stop                     Stop recording
  quit                     Shut down cleanly
"""

import os
import sys
import threading

from config import load_config
from core import WhispererCore


def main():
    debug = os.environ.get("WHISPERER_DEBUG", "").lower() in ("1", "true")

    def _early_debug(msg):
        if debug:
            print(f"DEBUG {msg}", flush=True)

    config = load_config(debug_log=_early_debug if debug else None)

    if debug:
        config["debug"] = True

    def _on_transcription_done():
        """Reliable completion signal — always fires after transcription pipeline finishes."""
        core.log("TRANSCRIPTION_DONE")

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
        on_transcription_done=_on_transcription_done,
    )

    core.log(f"Swift bridge starting... (PID: {os.getpid()}, Python: {sys.version})")

    if not core.verify_setup():
        core.log("ERROR: verify_setup failed")
        sys.exit(1)

    core.start()
    core.log("BRIDGE_READY")

    def read_commands():
        """Read commands from stdin until EOF or 'quit'."""
        try:
            for line in sys.stdin:
                cmd = line.strip()
                if not cmd:
                    continue

                # Always log commands for diagnostics
                core.log(f"[bridge] CMD: '{cmd}' (is_recording={core.is_recording})")

                if cmd == "quit":
                    core.log("Bridge shutting down.")
                    os._exit(0)

                elif cmd.startswith("start"):
                    parts = cmd.split()
                    use_large = "--large" in parts
                    keep_punct = "--punct" in parts

                    if core.is_recording:
                        core.log(f"[bridge] Already recording — ignoring start (is_recording={core.is_recording})")
                        continue

                    msg = "Starting recording"
                    if use_large:
                        msg += " with large model"
                    if keep_punct:
                        msg += " (keeping punctuation)"
                    core.log(msg + "...")
                    core.start_recording(
                        use_large_model=use_large,
                        keep_punctuation=keep_punct,
                    )
                    core.log(f"[bridge] After start_recording: is_recording={core.is_recording}")

                elif cmd == "stop":
                    core.log(f"[bridge] Processing stop: is_recording={core.is_recording}")
                    if core.is_recording:
                        core.stop_recording()
                        core.log(f"[bridge] After stop_recording: is_recording={core.is_recording}")
                    else:
                        core.log("[bridge] stop: NOT recording — ignoring")

                else:
                    core.log(f"Unknown command: '{cmd}'")

        except EOFError:
            core.log("Bridge stdin closed.")
        except Exception as e:
            core.log(f"Bridge command error: {e}")
        finally:
            os._exit(0)

    # Read commands on a background thread so we don't block
    cmd_thread = threading.Thread(target=read_commands, daemon=True)
    cmd_thread.start()
    cmd_thread.join()


if __name__ == "__main__":
    main()
