# Whisperer

Local voice-to-text for macOS using [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Hold a hotkey, speak, release — transcribed text is pasted into the active text field. All processing happens on-device with no cloud dependencies.

## Requirements

- **macOS 13.0+** (Ventura or later)
- **[Homebrew](https://brew.sh)** package manager
- **Python 3.10+** (installed via Homebrew in the install script)
- **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** — compiled locally with GGML model files

### macOS permissions

The app needs three permissions, granted in **System Settings > Privacy & Security**:

| Permission | Why |
|---|---|
| **Accessibility** | Simulates Cmd+V to paste transcribed text |
| **Input Monitoring** | Listens for global hotkey presses |
| **Microphone** | Records audio for transcription |

The app checks for these at startup and shows grant links in the menu bar if any are missing.

## Install

### 1. Clone the repo

```bash
git clone https://github.com/yourusername/whisperer.git
cd whisperer
```

### 2. Install system dependencies and Python packages

```bash
./scripts/install.sh
```

This runs:
- `brew install python@3.10 portaudio` ([PortAudio](http://www.portaudio.com/) is needed by PyAudio for mic access)
- `pip3 install -r requirements.txt` — installs: `numpy`, `pyaudio`, `pyperclip`, `pynput`, `pyyaml`

### 3. Build whisper.cpp and download models

```bash
./scripts/install_whispercpp.sh
```

This clones [whisper.cpp](https://github.com/ggerganov/whisper.cpp), compiles it with `make`, and downloads four GGML model files into its `models/` directory:

| Model | File | Used for |
|---|---|---|
| tiny.en | `ggml-tiny.en.bin` | Very short recordings (0–1.5s) |
| base.en | `ggml-base.en.bin` | Short recordings (1.5–3s) |
| small.en | `ggml-small.en.bin` | Normal recordings (3s+) |
| medium.en | `ggml-medium.en.bin` | Available for manual selection |

The script clones whisper.cpp into the current directory. Whisperer auto-detects it by searching these locations in order:

1. `$WHISPER_CPP_PATH` environment variable
2. `~/dev/whisper.cpp`
3. `~/Documents/GitHub/whisper.cpp`
4. `~/whisper.cpp`
5. `/opt/whisper.cpp`
6. `/usr/local/whisper.cpp`

Or set `whispercpp_folder` in the config file to an explicit path.

> **Note:** You can also download the `large-v3-turbo` model for higher-quality transcription (triggered manually via Left Cmd modifier). Download it from the whisper.cpp `models/` directory:
> ```bash
> cd whisper.cpp/models
> bash ./download-ggml-model.sh large-v3-turbo
> ```

### 4. Grant macOS permissions

Open **System Settings > Privacy & Security** and grant your terminal (or Whisperer.app) access to:

- **Accessibility** (under Privacy & Security > Accessibility)
- **Input Monitoring** (under Privacy & Security > Input Monitoring)
- **Microphone** (under Privacy & Security > Microphone) — the app will prompt for this on first launch

## Usage

There are two ways to run Whisperer:

### CLI mode

```bash
python3 whisperer/cli.py
```

Or with auto-restart on crash:

```bash
./scripts/run.sh
```

### Native menu bar app (recommended)

```bash
cd WhispererApp && ./build_and_run.sh
```

This builds a Swift app, bundles it as `Whisperer.app`, and launches it. The app lives in the menu bar with a waveform icon and provides:

- Status display (idle, recording, transcribing)
- Configurable hotkeys
- Model selection
- Custom vocabulary corrections
- Sound and appearance preferences

The Swift app requires **Xcode Command Line Tools** (`xcode-select --install`) for the Swift compiler.

## Hotkeys

### CLI mode (fixed)

| Combo | Action |
|---|---|
| Right Cmd + Right Option | Record and transcribe |
| + Left Cmd | Use large model (large-v3-turbo) |
| + Left Option | Keep punctuation in output |
| Release either key | Stop recording |

### Menu bar app

Hotkeys are configurable in **Preferences > Hotkeys**. Use `python3 whisperer/listener.py` to identify key codes for custom bindings.

### Cancel a transcription

Say **"cancel that"** during a recording to discard the transcription.

## How it works

1. Hold the hotkey to start recording from the microphone (16kHz, mono, 16-bit)
2. Release the hotkey to stop recording
3. Recordings under 0.2s are discarded as accidental presses
4. Short recordings (under 1.5s) are padded with silence to improve accuracy
5. A model is selected based on recording duration (or manually via Left Cmd)
6. whisper.cpp runs as a subprocess with anti-hallucination flags
7. Output is cleaned: bracketed/parenthesized content stripped, junk phrases removed, artifacts cleaned, whitespace collapsed
8. Cleaned text is copied to the clipboard and pasted via Cmd+V

## Configuration

Config lives at `~/.whisperer/config.yaml` (created automatically on first run with defaults):

```yaml
whispercpp_folder: ""          # auto-detected if empty (see search paths above)
prompt: "Voice dictation, clear speech, single speaker."
models:
  tiny.en: [0, 1.5]           # duration range in seconds
  base.en: [1.5, 3]
  small.en: [3, 999999]
enable_beeps: true             # master switch for all sounds
enable_start_sound: true
enable_stop_sound: true
enable_error_sound: true
sound_volume: 50               # 0–100
cleanup_recordings: true       # delete WAV files after transcription
debug: false
custom_words: {}               # {"mistranscribed": "correct", ...}
```

### Custom vocabulary

Add word corrections for terms whisper.cpp frequently gets wrong:

```yaml
custom_words:
  "whisper": "Whisper"
  "open source ai": "OpenAI"
```

Matching is case-insensitive. Corrections are applied after all other text cleaning.

## Debugging

Enable debug logging any of three ways:

```bash
python3 whisperer/cli.py --debug          # CLI flag
WHISPERER_DEBUG=1 python3 whisperer/cli.py  # environment variable
```

Or set `debug: true` in `~/.whisperer/config.yaml`.

Debug output is tagged by subsystem (`[config]`, `[record]`, `[transcribe]`, `[clean]`, `[hotkey]`, etc.) with millisecond timestamps. Logs are written to `~/whisperer_debug.log` (override with `--log-file`).

The menu bar app writes its own diagnostic log — accessible via the **Show Diagnostic Log** menu item.

## Project structure

```
whisperer/              Python package
  cli.py                CLI entry point (hotkey listener)
  core.py               Engine: recording, transcription, text cleaning, clipboard paste
  config.py             YAML config loader + whisper.cpp auto-detection
  phrases.py            Junk phrases stripped from transcriptions
  swift_bridge.py       Bridge between Swift GUI and Python engine
  listener.py           Debug tool: prints key names for custom hotkey setup
WhispererApp/           Native Swift menu bar app
  build_and_run.sh      Build, bundle, code-sign, and launch
  Package.swift         Swift package definition (depends on Yams for YAML parsing)
  Sources/              Swift source code (AppDelegate, views, services, models)
scripts/
  install.sh            System deps + Python packages
  install_whispercpp.sh whisper.cpp build + model downloads
  run.sh                CLI with auto-restart on crash
assets/Sounds/          Audio feedback sounds (.aiff)
```

## License

MIT
