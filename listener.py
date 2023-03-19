"""
Global keyboard listener tester using pynput (no window needed).

Usage:
  1) Install dependency once:  pip install pynput
  2) Run:  python listener.py
  3) Press keys to see their names. Press ESC to exit.

This is useful for debugging hotkey combinations and identifying
key names on your system.
"""

import sys
import platform
import threading
import time

from pynput import keyboard

print("Press keys to see their names. Press ESC to exit.\n")
print(f"Python: {sys.version.split()[0]} | Platform: {platform.system()} {platform.release()} | Interpreter: {sys.executable}", flush=True)
print()

_events = {"press": 0, "release": 0}

# Watchdog to report if nothing is being seen (helps diagnose permissions)
def _watchdog():
    last = (0, 0)
    while True:
        time.sleep(5)
        snap = (_events["press"], _events["release"])
        if snap == last:
            print("[watchdog] No input events detected in last 5s. If on macOS: grant Terminal/PyCharm in Accessibility and Input Monitoring; restart the app.", flush=True)
        else:
            print(f"[watchdog] Events so far — press:{snap[0]} release:{snap[1]}", flush=True)
        last = snap

threading.Thread(target=_watchdog, daemon=True).start()


def on_key_press(key):
    _events["press"] += 1
    # Stop on ESC
    if key == keyboard.Key.esc:
        print("\nESC pressed — exiting...", flush=True)
        return False  # stop keyboard listener
    
    # Print detailed key info
    try:
        print(f"Key pressed: {key} (char: {key.char})", flush=True)
    except AttributeError:
        # Special key (no char attribute)
        print(f"Key pressed: {key}", flush=True)


def on_key_release(key):
    _events["release"] += 1
    try:
        print(f"Key released: {key} (char: {key.char})", flush=True)
    except AttributeError:
        print(f"Key released: {key}", flush=True)


# Start listener
keyboard_listener = keyboard.Listener(on_press=on_key_press, on_release=on_key_release)
keyboard_listener.start()

# Wait for listener to finish (ESC will stop it)
keyboard_listener.join()