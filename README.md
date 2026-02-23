# Whisperer

Local voice-to-text for macOS using [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Hold a hotkey, speak, release — transcribed text is pasted into the active text field. All processing happens on-device.

## Setup

Requires macOS, Python 3.10+, and [Homebrew](https://brew.sh).

```bash
./scripts/install.sh
./scripts/install_whispercpp.sh
```

Then grant **Accessibility** and **Input Monitoring** permissions in System Settings > Privacy & Security.

## Usage

```bash
python3 whisperer/cli.py       # CLI
./scripts/run.sh               # CLI with auto-restart
cd WhispererApp && ./build_and_run.sh  # native menu bar app
```

## Hotkeys

| Combo | Action |
|-------|--------|
| Right Cmd + Right Option | Record and transcribe |
| + Left Cmd | Use large model |
| + Left Option | Keep punctuation |
| Release either key | Stop recording |

Say "cancel that" to discard a transcription.

## How it works

Hold the hotkey to record from the mic. On release, whisper.cpp transcribes the audio locally. The output is cleaned (hallucination phrases stripped, artifacts removed) and pasted via Cmd+V.

Models are chosen by duration: tiny.en (0–1.5s), base.en (1.5–3s), small.en (3s+), or large-v3-turbo (manual via Left Cmd).

## Configuration

`~/.whisperer/config.yaml` (created on first run):

```yaml
whispercpp_folder: ""          # auto-detected if empty
prompt: "Voice dictation, clear speech, single speaker."
models:
  tiny.en: [0, 1.5]
  base.en: [1.5, 3]
  small.en: [3, 999999]
enable_beeps: true
cleanup_recordings: true
debug: false
```

## Debug

```bash
python3 whisperer/cli.py --debug
```

Or set `WHISPERER_DEBUG=1` or `debug: true` in config. Output is tagged by subsystem (`[record]`, `[transcribe]`, `[clean]`, `[hotkey]`, etc.) with millisecond timestamps.

## Project structure

```
whisperer/          Python package (cli, core, config, phrases, swift_bridge, listener)
WhispererApp/       Native Swift menu bar app
assets/Sounds/      Audio feedback sounds
scripts/            install.sh, install_whispercpp.sh, run.sh
```

## License

MIT
