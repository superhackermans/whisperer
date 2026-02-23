# Whisperer

Local voice-to-text for macOS using [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Hold a hotkey, speak, release -- transcribed text is pasted into whatever text field is active.

All processing happens on-device. No data leaves your machine.

## Installation

### Prerequisites

- macOS
- Python 3.10+
- [Homebrew](https://brew.sh)

### Quick setup

```bash
# 1. Install system dependencies and Python packages
./scripts/install.sh

# 2. Clone, compile whisper.cpp, and download models
./scripts/install_whispercpp.sh
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
python3 whisperer/cli.py
```

### Auto-restart wrapper

Survives whisper.cpp segfaults by restarting automatically:

```bash
./scripts/run.sh
```

### Native menu bar app (Swift)

Build and run the native macOS menu bar app:

```bash
cd WhispererApp
./build_and_run.sh
```

## Hotkeys

| Combo | Action |
|-------|--------|
| Right Cmd + Right Option | Record and transcribe |
| + Left Cmd | Use large model (large-v3-turbo) |
| + Left Option | Keep punctuation in output |
| Release either key | Stop recording |

Say **"cancel that"** during recording to discard the transcription.

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
python3 whisperer/cli.py --debug
# or
WHISPERER_DEBUG=1 python3 whisperer/cli.py
```

Debug output is tagged by subsystem (`[record]`, `[transcribe]`, `[clean]`, `[hotkey]`, etc.) with millisecond timestamps.

## Project structure

```
whisperer/                Python package
  cli.py                  CLI entry point (hotkey listener)
  core.py                 Engine: recording, transcription, text cleaning, clipboard paste
  config.py               YAML config loader + whisper.cpp auto-detection
  phrases.py              Known hallucination phrases to strip
  swift_bridge.py         Bridge between Swift GUI and Python engine
  listener.py             Debug tool: prints key names for hotkey identification
WhispererApp/             Native Swift menu bar app
assets/                   Icons and sound files
  Sounds/                 Audio feedback sound files
scripts/                  Shell scripts
  install.sh              System deps + Python packages installer
  install_whispercpp.sh   whisper.cpp build + model download script
  run.sh                  Auto-restart wrapper
```

## License

MIT
