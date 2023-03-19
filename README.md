# Whisperer

Local voice-to-text for macOS using [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Hold a hotkey, speak, release -- transcribed text is pasted into whatever text field is active.

All processing happens on-device. No data leaves your machine.

## Why

Built-in dictation mangles technical terms. Whisper running locally handles them well:

| Source | Transcription |
|--------|--------------|
| Original | Popular Linux distributions include Debian, Fedora Linux, and Ubuntu. You can use windowing systems such as X11 or Wayland with a desktop environment like KDE Plasma. |
| iPhone dictation | Popular Linux distributions include Debby and Fed or Linux, and do Bantu. You can use windowing systems such as X eleven or Weiland with a desktop environment like KD plasma. |
| **Whisperer** | Popular Linux distributions include Debian, Fedora, Linux, and Ubuntu. You can use windowing systems such as X11 or Wayland with a desktop environment like KDE Plasma. |

## Installation

### Prerequisites

- macOS
- Python 3.10+
- [Homebrew](https://brew.sh)

### Quick setup

```bash
# 1. Install system dependencies and Python packages
./install.sh

# 2. Clone, compile whisper.cpp, and download models
./install_whispercpp.sh
```

### Manual setup

```bash
brew install python@3.10 portaudio
pip3 install -r requirements.txt
```

### Permissions

Grant your terminal (or the bundled .app) **Accessibility** and **Input Monitoring** permissions in **System Settings > Privacy & Security**.

## Usage

### CLI mode (recommended)

```bash
python3 whisperer.py
```

### Auto-restart wrapper

Survives whisper.cpp segfaults by restarting automatically:

```bash
./run.sh
```

### Menu bar app

```bash
python3 whisperergui.py
```

Provides a macOS menu bar icon with model selection, keybinding configuration, and manual start/stop controls.

### Building the .app bundle

```bash
python3 setup.py py2app
```

## Hotkeys

### CLI mode

| Combo | Action |
|-------|--------|
| Right Cmd + Right Option | Record and transcribe |
| + Left Cmd | Use large model (large-v3-turbo) |
| + Left Option | Keep punctuation in output |
| Release either key | Stop recording |

Say **"cancel that"** during recording to discard the transcription.

### GUI mode

Default keybinding is **Cmd + Option** (configurable via the menu bar). The GUI also supports Shift + Option and Cmd + Shift.

## How it works

1. **Record** -- Listens for the hotkey via pynput, then captures audio from the mic (PyAudio, 16kHz mono)
2. **Pad** -- Short recordings (<1.5s) are padded with silence at the end to meet whisper.cpp's minimum (front-padding is avoided as it triggers hallucinations)
3. **Transcribe** -- Runs whisper.cpp as a subprocess with anti-hallucination flags
4. **Clean** -- Strips hallucinated YouTube outros, bracketed content, prompt leakage, and other artifacts
5. **Paste** -- Copies cleaned text to clipboard and pastes via Cmd+V

### Model selection

Models are chosen automatically by recording duration:

| Model | Duration range |
|-------|---------------|
| tiny.en | 0 -- 1.5s |
| base.en | 1.5 -- 3s |
| small.en | 3s+ |
| large-v3-turbo | Manual (hold Left Cmd) |

### Anti-hallucination measures

Whisperer applies several techniques to reduce whisper.cpp hallucinations:

- **`-nt`** -- Disables timestamp computation (biggest single reducer)
- **`-mc 0`** -- No prior-segment context carry-over
- **`--no-speech-thold 0.4`** -- Stricter silence detection
- **`--logprob-thold -0.5`** -- Rejects low-confidence output
- **End-only padding** -- Front-padding triggers hallucinated phrases
- **Junk phrase filter** -- Strips ~160 known hallucination phrases (YouTube outros, etc.)
- **Recordings < 0.2s discarded** -- Too short to produce meaningful output

## Configuration

Whisperer reads configuration from `~/.whisperer/config.yaml`. A default config is created on first run.

```yaml
# Path to whisper.cpp installation (auto-detected if empty)
whispercpp_folder: ""

# Prompt sent to whisper.cpp for context
prompt: "Voice dictation, clear speech, single speaker."

# Model selection by duration range [min, max] in seconds
models:
  tiny.en: [0, 1.5]
  base.en: [1.5, 3]
  small.en: [3, 999999]

# Audio feedback beeps on record start/stop
enable_beeps: true

# Delete WAV/TXT files after transcription
cleanup_recordings: true

# Verbose debug logging
debug: false
```

Auto-detection searches for whisper.cpp in: `$WHISPER_CPP_PATH`, `~/Documents/GitHub/whisper.cpp`, `~/whisper.cpp`, `/opt/whisper.cpp`, `/usr/local/whisper.cpp`.

## Debug mode

Enable with any of:
- `--debug` flag
- `WHISPERER_DEBUG=1` environment variable
- `debug: true` in config

```bash
python3 whisperer.py --debug
# or
WHISPERER_DEBUG=1 python3 whisperer.py
```

Debug output is tagged by subsystem (`[record]`, `[transcribe]`, `[clean]`, `[hotkey]`, etc.) with millisecond timestamps.

## Project structure

```
whisperer.py          CLI entry point (hotkey listener)
whisperergui.py       macOS menu bar app (rumps)
core.py               Engine: recording, transcription, text cleaning, clipboard paste
config.py             YAML config loader + whisper.cpp auto-detection
phrases.py            Known hallucination phrases to strip
listener.py           Debug tool: prints key names for hotkey identification
setup.py              py2app config for bundling as .app
install.sh            System deps + Python packages installer
install_whispercpp.sh whisper.cpp build + model download script
run.sh                Auto-restart wrapper
Sounds/               Audio feedback sound files
```

## License

MIT
