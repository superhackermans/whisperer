# Whisperer

macOS voice-to-text app using whisper.cpp for local speech transcription. Hold a hotkey combo, speak, release — transcribed text is pasted into the active text field via clipboard.

## Architecture

```
whisperer/                Python package
  cli.py                  CLI entry point (hotkey listener)
  core.py                 Engine: recording, transcription, text cleaning, clipboard paste
  config.py               YAML config loader (~/.whisperer/config.yaml) + whisper.cpp auto-detect
  phrases.py              List of junk phrases to strip from transcriptions
  swift_bridge.py         Bridge between Swift GUI and Python engine
  listener.py             Debug tool: prints key names to identify hotkey codes
WhispererApp/             Native Swift menu bar app (configurable hotkeys, menu bar icon)
scripts/                  Shell scripts
  install.sh              System deps + Python packages installer
  install_whispercpp.sh   whisper.cpp build + model download script
  run.sh                  Auto-restart wrapper
assets/                   Icons and sound files
  Sounds/                 Audio feedback sound files
```

### Threading model

- **Main thread**: runs pynput keyboard listener (blocking)
- **Recording thread** (daemon): captures audio via PyAudio, spawned per recording session
- **Transcription worker** (daemon): dequeues WAV files, runs whisper.cpp subprocess, cleans text, pastes via Cmd+V

Thread safety: `threading.Lock` guards `_recording` and `_frames`; `queue.Queue` passes audio files to the transcription worker.

### Data flow

```
Hotkey press → record audio → save WAV (padded to 5s) → queue
  → whisper.cpp subprocess → read .txt output → clean_transcription()
  → clipboard copy → Cmd+V paste
```

## Dependencies

**Python packages**: pynput, pyaudio, pyperclip, numpy, pyyaml

**External**: whisper.cpp compiled binary + GGML model files. Default location: `~/Documents/GitHub/whisper.cpp/`

**System**: macOS with Accessibility + Input Monitoring permissions granted to the terminal.

## Install & Run

```bash
# Install system deps + Python packages
./scripts/install.sh

# Build and download whisper.cpp models
./scripts/install_whispercpp.sh

# Run CLI
python3 whisperer/cli.py

# Auto-restart wrapper
./scripts/run.sh

# Native Swift menu bar app
cd WhispererApp && ./build_and_run.sh
```

## Hotkeys (CLI mode)

| Combo | Action |
|-------|--------|
| Right Cmd + Right Option | Record & transcribe |
| + Left Cmd | Use large model (large-v3-turbo) |
| + Left Option | Keep punctuation in output |
| Release either key | Stop recording |

## Key constants

- `CHUNK = 512`, `RATE = 16000`, mono 16-bit audio
- Recordings < 0.2s are discarded
- Recordings < 1.5s are padded with silence at the end only (front-padding triggers hallucinations)
- Model selection by duration: base.en (0-3s), small.en (3s+), large-v3-turbo (manual)
- "cancel that" in output → discard transcription

## Anti-hallucination flags (whisper.cpp)

- `-nt` — disables timestamp computation (biggest single reducer)
- `-mc 0` — no prior-segment context carry-over (prevents hallucination propagation)
- `--no-speech-thold 0.4` — stricter silence detection (default 0.6)
- `--logprob-thold -0.5` — rejects low-confidence hallucinated output (default -1.0)
- Prompt is descriptive ("Voice dictation, clear speech, single speaker."), not instructional

## Text cleaning pipeline (whisperer/core.py `clean_transcription`)

1. Strip `[bracketed]` and `(parenthesized)` content
2. Strip `$` artifacts (prompt leakage)
3. Strip `#` and everything after
3. Strip known junk phrases (phrases.py — YouTube outros, etc.)
4. Strip trailing ". you" / "? you"
5. Normalize ellipses (unless keep_punctuation)
6. Deduplicate "word. word" → "word."
7. Collapse whitespace

## Debug mode

Enable with any of: `--debug` flag, `WHISPERER_DEBUG=1` env var, or `debug: true` in config.

All debug lines are prefixed with `DEBUG` and tagged by subsystem:

| Tag | What it traces |
|-----|----------------|
| `[config]` | Config file loading, YAML parsing, key overrides, whisper.cpp auto-detect |
| `[cli]` | CLI argument parsing, env var reads, config overrides |
| `[init]` | WhispererCore constructor — all resolved settings |
| `[setup]` | Binary/model verification, flag probing, sound file checks |
| `[sound]` | Which sound plays, skips (beeps disabled / file missing) |
| `[audio]` | PyAudio init, device enumeration, default input device info |
| `[record]` | Thread start, stream params, frame counts, wall time, read errors |
| `[frames]` | Frame count, byte totals, duration calc, padding, WAV write, queue depth |
| `[model]` | Each model checked with range, match result, final selection |
| `[transcribe]` | Full command line, subprocess timing, stdout/stderr, output file size |
| `[clean]` | Every text-cleaning step that changes the text, sentence count |
| `[paste]` | Clipboard copy, verification, each Cmd+V retry attempt |
| `[cleanup]` | File removal with sizes, or skip reason |
| `[callback]` | on_error / on_transcribing / on_transcription_done firings |
| `[hotkey]` | Every key press/release with full modifier state |
| `[gui]` | Menu clicks, model/keybinding changes, state transitions |
| `[gui-hotkey]` | GUI-mode key press/release with modifier state |

Timestamps include milliseconds: `[2026-02-19 14:30:22.417]`

## Code style

- No type stubs or mypy. Type hints used sparingly (function signatures only).
- Logging via `WhispererCore.log()` — writes to both stdout and a log file.
- `WhispererCore.log_debug()` — debug-only, prefixed with `DEBUG`, tagged by subsystem.
- `WHISPERER_DEBUG=1` env var, `--debug` flag, or `debug: true` in config enables debug logging.
- macOS-only: no cross-platform abstractions.
