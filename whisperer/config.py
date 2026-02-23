"""
Configuration management for Whisperer.

Handles loading/saving YAML config from ~/.whisperer/config.yaml
and auto-detection of whisper.cpp installation.
"""

import os

import yaml

CONFIG_DIR = os.path.expanduser("~/.whisperer")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.yaml")

DEFAULT_CONFIG = {
    "whispercpp_folder": "",
    "prompt": "Voice dictation, clear speech, single speaker.",
    "models": {
        "tiny.en": [0, 1.5],
        "base.en": [1.5, 3],
        "small.en": [3, 999999],
    },
    "enable_beeps": True,
    "enable_start_sound": True,
    "enable_stop_sound": True,
    "enable_error_sound": True,
    "sound_volume": 50,
    "cleanup_recordings": True,
    "debug": False,
    "custom_words": {},
}

# Searched in order when whispercpp_folder is empty
_WHISPER_SEARCH_PATHS = [
    "~/dev/whisper.cpp",
    "~/Documents/GitHub/whisper.cpp",
    "~/whisper.cpp",
    "/opt/whisper.cpp",
    "/usr/local/whisper.cpp",
]


def find_whispercpp(debug_log=None):
    """Auto-detect whisper.cpp installation. Returns path or None."""
    # 1. Environment variable
    env = os.environ.get("WHISPER_CPP_PATH")
    if env:
        path = os.path.expanduser(env)
        binary = os.path.join(path, "main")
        if os.path.isfile(binary):
            if debug_log:
                debug_log(f"[config] Found whisper.cpp via $WHISPER_CPP_PATH: {path}")
            return path
        elif debug_log:
            debug_log(f"[config] $WHISPER_CPP_PATH={env} but no binary at {binary}")

    # 2. Search known paths
    for p in _WHISPER_SEARCH_PATHS:
        path = os.path.expanduser(p)
        binary = os.path.join(path, "main")
        if os.path.isfile(binary):
            if debug_log:
                debug_log(f"[config] Found whisper.cpp at search path: {path}")
            return path
        elif debug_log:
            debug_log(f"[config] No binary at {binary}")

    if debug_log:
        debug_log("[config] whisper.cpp not found in any search path")
    return None


def load_config(debug_log=None):
    """Load config from ~/.whisperer/config.yaml, creating defaults if needed.

    Returns a dict with all config keys guaranteed present.
    """
    config = dict(DEFAULT_CONFIG)

    if os.path.exists(CONFIG_PATH):
        if debug_log:
            debug_log(f"[config] Loading config from {CONFIG_PATH}")
        try:
            with open(CONFIG_PATH) as f:
                raw = f.read()
            if debug_log:
                debug_log(f"[config] Raw YAML ({len(raw)} bytes):\n{raw.rstrip()}")
            user_config = yaml.safe_load(raw) or {}
            overridden = [k for k in user_config if k in DEFAULT_CONFIG]
            new_keys = [k for k in user_config if k not in DEFAULT_CONFIG]
            if debug_log:
                debug_log(f"[config] Keys overriding defaults: {overridden}")
                if new_keys:
                    debug_log(f"[config] Unknown keys (ignored by core): {new_keys}")
            config.update(user_config)
        except Exception as e:
            if debug_log:
                debug_log(f"[config] Failed to parse {CONFIG_PATH}: {e} — using defaults")
    else:
        if debug_log:
            debug_log(f"[config] No config file at {CONFIG_PATH} — creating defaults")
        save_config(config)

    # Convert model ranges from lists to tuples of floats.
    # Yams (Swift YAML library) writes 0.0 as "0e+0" which PyYAML may
    # parse as a string instead of a float. Force float() conversion.
    models = {}
    for name, val in config["models"].items():
        if isinstance(val, (list, tuple)) and len(val) == 2:
            try:
                models[name] = (float(val[0]), float(val[1]))
            except (ValueError, TypeError):
                if debug_log:
                    debug_log(f"[config] WARNING: bad range for {name}: {val} — treating as manual-only")
                models[name] = None
        else:
            models[name] = val
    config["models"] = models

    # Validate custom_words: must be a dict with string keys and values
    raw_words = config.get("custom_words", {})
    if isinstance(raw_words, dict):
        clean_words = {}
        for k, v in raw_words.items():
            sk, sv = str(k), str(v)
            if sk and sv:
                clean_words[sk] = sv
            elif debug_log:
                debug_log(f"[config] Skipping invalid custom_words entry: {k!r} -> {v!r}")
        config["custom_words"] = clean_words
    else:
        if debug_log:
            debug_log(f"[config] custom_words is not a dict ({type(raw_words).__name__}) — using empty")
        config["custom_words"] = {}

    # Auto-detect whisper.cpp if not set
    if not config.get("whispercpp_folder"):
        if debug_log:
            debug_log("[config] whispercpp_folder not set — searching...")
        detected = find_whispercpp(debug_log)
        if detected:
            config["whispercpp_folder"] = detected
    elif debug_log:
        debug_log(f"[config] whispercpp_folder from config: {config['whispercpp_folder']}")

    if debug_log:
        safe = {k: v for k, v in config.items()}
        debug_log(f"[config] Final resolved config: {safe}")

    return config


def save_config(config):
    """Write config to ~/.whisperer/config.yaml."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    # Convert tuples back to lists for YAML
    out = dict(config)
    models = {}
    for name, val in out.get("models", {}).items():
        if isinstance(val, tuple):
            models[name] = list(val)
        else:
            models[name] = val
    out["models"] = models
    with open(CONFIG_PATH, "w") as f:
        yaml.dump(out, f, default_flow_style=False, sort_keys=False)
