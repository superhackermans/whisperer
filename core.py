"""
Shared recording and transcription engine for Whisperer.

Provides:
  - WhispererCore: thread-safe class that handles audio recording,
    whisper.cpp transcription, text cleaning, and clipboard paste.
  - run_hotkey_listener: standard Right Cmd + Right Option hotkey loop.
  - clean_transcription: standalone text-cleaning function.
"""

import os
import queue
import re
import shlex
import subprocess
import sys
import threading
import time
import traceback
import wave
from datetime import datetime

import numpy as np
import pyaudio
import pyperclip
from pynput import keyboard

from phrases import phrases_to_remove

# ---------------------------------------------------------------------------
# Compile the ending-phrases regex once at import time
# ---------------------------------------------------------------------------
_ENDING_PHRASES_PATTERN = re.compile(
    r"\b(?:{})\b[.!?]*\s*$".format("|".join(map(re.escape, phrases_to_remove))),
    flags=re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Audio constants
# ---------------------------------------------------------------------------
CHUNK = 512
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 16000

# ---------------------------------------------------------------------------
# Audio feedback sounds (relative to this file's directory)
# ---------------------------------------------------------------------------
_SOUNDS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "Sounds")
_SOUND_START = os.path.join(_SOUNDS_DIR, "Pop Short.aiff")
_SOUND_STOP = os.path.join(_SOUNDS_DIR, "Pop.aiff")
_SOUND_ERROR = os.path.join(_SOUNDS_DIR, "Basso.aiff")
_SOUND_VOLUME = 50  # 0-100, afplay volume percentage

# ---------------------------------------------------------------------------
# Anti-hallucination flags to probe for in whisper.cpp --help
# ---------------------------------------------------------------------------
_OPTIONAL_FLAGS = [
    (["-mc", "0"], "-mc"),
    (["--no-speech-thold", "0.4"], "--no-speech-thold"),
    (["--logprob-thold", "-0.5"], "--logprob-thold"),
]


# ---------------------------------------------------------------------------
# Text cleaning
# ---------------------------------------------------------------------------
def clean_transcription(text: str, keep_punctuation: bool = False,
                        debug_log=None) -> str:
    """Clean a raw whisper.cpp transcription.

    If *debug_log* is a callable, it receives a string after every cleaning
    step so you can see exactly which rule changed the text.
    """
    if debug_log:
        def _apply(label, new_text):
            nonlocal text
            if new_text != text:
                debug_log(f"  [clean] {label}: '{text}' -> '{new_text}'")
            text = new_text
    else:
        def _apply(_, new_text):
            nonlocal text
            text = new_text

    # Remove bracketed / parenthesised content
    _apply("strip [brackets]", re.sub(r"\[.*?\]", "", text))
    _apply("strip (parens)", re.sub(r"\(.*?\)", "", text))

    # Remove dollar-sign artifacts leaked from prompts
    _apply("strip $ artifacts", re.sub(r"\$+", "", text))

    # Remove "#" and everything after it
    _apply("strip # and after", re.sub(r"#.*", "", text).strip())

    # Remove known ending phrases
    _apply("strip junk phrases", _ENDING_PHRASES_PATTERN.sub("", text).strip())

    # Remove trailing ". you" / "? you"
    _apply(
        "strip trailing you",
        re.sub(r"([.!?])\s*you\s*$", r"\1", text, flags=re.IGNORECASE).strip(),
    )

    # Handle ellipses and trailing periods
    if not keep_punctuation:
        sentence_count = len(re.findall(r"[.!?]", text))
        if debug_log:
            debug_log(f"  [clean] sentence_count={sentence_count}, keep_punctuation={keep_punctuation}")
        if sentence_count > 1:
            _apply("collapse ellipses (multi-sentence)", re.sub(r"\.\.\.+", ".", text))
        elif sentence_count == 1:
            _apply("remove ellipses (single-sentence)", re.sub(r"\.\.\.+", "", text).strip())
            if text.endswith("."):
                _apply("strip trailing period", text[:-1].strip())

    # Remove duplicate words split by a period  ("word. word" → "word.")
    _apply(
        "dedup word.word",
        re.sub(r"\b(\w+)\.\s+\1\b", r"\1.", text, flags=re.IGNORECASE),
    )

    # Collapse whitespace
    _apply("collapse whitespace", re.sub(r"\s+", " ", text).strip())

    return text


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------
class WhispererCore:
    """Thread-safe recording + transcription engine."""

    def __init__(
        self,
        recordings_folder="~/Documents/whispers",
        whispercpp_folder="~/Documents/GitHub/whisper.cpp",
        log_file="~/whisperer_debug.log",
        models=None,
        prompt="Voice dictation, clear speech, single speaker.",
        debug=False,
        cleanup_recordings=True,
        enable_beeps=True,
        enable_start_sound=True,
        enable_stop_sound=True,
        enable_error_sound=True,
        sound_volume=50,
        on_error=None,
        on_transcribing=None,
        on_transcription_done=None,
    ):
        self.recordings_folder = os.path.expanduser(recordings_folder)
        self.whispercpp_folder = os.path.expanduser(whispercpp_folder)
        self.log_file = os.path.expanduser(log_file)
        self.prompt = prompt
        self.debug = debug
        self.cleanup_recordings = cleanup_recordings
        self.enable_beeps = enable_beeps
        self.enable_start_sound = enable_start_sound
        self.enable_stop_sound = enable_stop_sound
        self.enable_error_sound = enable_error_sound
        self.sound_volume = sound_volume
        self.models = models or {
            "tiny.en": (0, 1.5),
            "base.en": (1.5, 3),
            "small.en": (3, 99999999999999),
            "large-v3-turbo": None,
        }

        # Optional callbacks for GUI integration
        self._on_error = on_error
        self._on_transcribing = on_transcribing
        self._on_transcription_done = on_transcription_done

        # Supported anti-hallucination flags (populated by verify_setup)
        self._extra_flags = []

        # Thread-safe state
        self._lock = threading.Lock()
        self._recording = False
        self._audio = None          # lazy-initialised PyAudio
        self._frames = []
        self._audio_queue = queue.Queue()
        self._keyboard_controller = keyboard.Controller()

        os.makedirs(self.recordings_folder, exist_ok=True)

        # Global exception hook so crashes are logged
        self._original_excepthook = sys.excepthook
        sys.excepthook = self._excepthook

        if self.debug:
            self.log_debug(f"[init] recordings_folder={self.recordings_folder}")
            self.log_debug(f"[init] whispercpp_folder={self.whispercpp_folder}")
            self.log_debug(f"[init] log_file={self.log_file}")
            self.log_debug(f"[init] prompt='{self.prompt}'")
            self.log_debug(f"[init] models={self.models}")
            self.log_debug(f"[init] enable_beeps={self.enable_beeps}")
            self.log_debug(f"[init] cleanup_recordings={self.cleanup_recordings}")
            self.log_debug(f"[init] debug={self.debug}")
            self.log_debug(f"[init] callbacks: on_error={on_error is not None}, "
                           f"on_transcribing={on_transcribing is not None}, "
                           f"on_transcription_done={on_transcription_done is not None}")

    # ------------------------------------------------------------------ log
    def log(self, msg):
        """Log to stdout and log file."""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        log_msg = f"[{timestamp}] {msg}"
        print(log_msg, flush=True)
        try:
            with open(self.log_file, "a") as f:
                f.write(log_msg + "\n")
        except Exception:
            pass

    def log_debug(self, msg):
        """Log only when debug mode is enabled."""
        if self.debug:
            self.log(f"DEBUG {msg}")

    def log_exception(self, context):
        """Log the current exception with full traceback."""
        self.log(f"EXCEPTION in {context}:")
        self.log(traceback.format_exc())

    def _excepthook(self, exc_type, exc, tb):
        self.log_exception("Uncaught exception")
        traceback.print_exception(exc_type, exc, tb)

    # -------------------------------------------------------------- sounds
    def _play_sound(self, sound_path):
        """Play a macOS system sound in a background thread (non-blocking)."""
        if not self.enable_beeps:
            if self.debug:
                self.log_debug(f"[sound] Beeps disabled, skipping {os.path.basename(sound_path)}")
            return
        if not os.path.exists(sound_path):
            if self.debug:
                self.log_debug(f"[sound] Sound file not found: {sound_path}")
            return
        if self.debug:
            self.log_debug(f"[sound] Playing {os.path.basename(sound_path)} at volume {self.sound_volume}")
        vol = max(0, min(100, self.sound_volume))
        threading.Thread(
            target=lambda: subprocess.run(
                ["afplay", "-v", str(vol / 100), sound_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ),
            daemon=True,
        ).start()

    def _beep_start(self):
        if self.enable_start_sound:
            self._play_sound(_SOUND_START)
        elif self.debug:
            self.log_debug("[sound] Start sound disabled")

    def _beep_stop(self):
        if self.enable_stop_sound:
            self._play_sound(_SOUND_STOP)
        elif self.debug:
            self.log_debug("[sound] Stop sound disabled")

    def _beep_error(self):
        if self.enable_error_sound:
            self._play_sound(_SOUND_ERROR)
        elif self.debug:
            self.log_debug("[sound] Error sound disabled")

    # ----------------------------------------------------------- callbacks
    def _notify_error(self, title, message):
        """Log an error and fire the on_error callback if set."""
        self.log(f"{title}: {message}")
        self._beep_error()
        if self._on_error:
            if self.debug:
                self.log_debug(f"[callback] Firing on_error('{title}', '{message}')")
            try:
                self._on_error(title, message)
            except Exception:
                self.log_exception("on_error callback")

    # ------------------------------------------------------------- audio IO
    def _get_audio(self):
        """Lazy-initialise PyAudio (avoids crash if no device at import)."""
        if self._audio is None:
            self.log_debug("[audio] Initialising PyAudio...")
            self._audio = pyaudio.PyAudio()
            if self.debug:
                device_count = self._audio.get_device_count()
                self.log_debug(f"[audio] PyAudio initialised, {device_count} device(s) found")
                default_input = self._audio.get_default_input_device_info()
                self.log_debug(f"[audio] Default input device: '{default_input['name']}' "
                               f"(index={default_input['index']}, "
                               f"rate={default_input['defaultSampleRate']}, "
                               f"channels={default_input['maxInputChannels']})")
        return self._audio

    @property
    def is_recording(self):
        with self._lock:
            return self._recording

    def start_recording(self, use_large_model=False, keep_punctuation=False):
        """Begin recording. Returns immediately; audio capture runs in a new thread."""
        with self._lock:
            if self._recording:
                self.log(f"start_recording: ALREADY RECORDING — ignoring (use_large={use_large_model})")
                return
            # Set _recording immediately so stop_recording() can find it.
            # Without this, a quick "stop" arriving before the thread initialises
            # PyAudio would see _recording=False and be silently ignored.
            self._recording = True
            self.log(f"start_recording: _recording=True (use_large={use_large_model}, keep_punct={keep_punctuation})")
        self._beep_start()
        t = threading.Thread(
            target=self._record_audio,
            args=(use_large_model, keep_punctuation),
            daemon=True,
        )
        t.start()
        self.log(f"start_recording: thread spawned (name={t.name})")

    def stop_recording(self):
        """Signal the recording thread to stop."""
        with self._lock:
            if self._recording:
                self.log("Stopping recording...")
                self.log("stop_recording: _recording -> False")
                self._recording = False
                self._beep_stop()
            else:
                self.log("stop_recording: NOT recording — ignoring")

    def _record_audio(self, use_large_model, keep_punctuation):
        """Internal: capture audio until ``_recording`` is cleared."""
        t_start = time.time()

        self.log(f"_record_audio: thread={threading.current_thread().name}, _recording={self.is_recording}")

        try:
            audio = self._get_audio()
        except Exception as e:
            self._notify_error("Recording failed", f"Could not initialise PyAudio: {e}")
            self.log_exception("PyAudio init")
            with self._lock:
                self._recording = False
            self.log("_record_audio: PyAudio init failed, _recording=False")
            self._signal_done_if_needed()
            return

        self.log_debug(f"[record] Opening stream: format={FORMAT}, channels={CHANNELS}, "
                       f"rate={RATE}, chunk={CHUNK}")
        try:
            stream = audio.open(
                format=FORMAT,
                channels=CHANNELS,
                rate=RATE,
                input=True,
                frames_per_buffer=CHUNK,
            )
        except Exception as e:
            self._notify_error("Recording failed", f"Could not open microphone: {e}")
            self.log_exception("open stream")
            with self._lock:
                self._recording = False
            self.log("_record_audio: stream open failed, _recording=False")
            self._signal_done_if_needed()
            return

        # _recording was already set True by start_recording(); just clear frames.
        with self._lock:
            still_recording = self._recording
            self._frames = []

        if not still_recording:
            self.log("_record_audio: _recording already False (stop arrived during init) — exiting immediately")
            try:
                stream.stop_stream()
                stream.close()
            except Exception:
                pass
            self._signal_done_if_needed()
            return

        self.log("Recording started.")
        if self.debug:
            self.log_debug(f"[record] Stream active={stream.is_active()}, "
                           f"stopped={stream.is_stopped()}")

        read_errors = 0
        while True:
            with self._lock:
                if not self._recording:
                    break
            try:
                data = stream.read(CHUNK, exception_on_overflow=False)
                with self._lock:
                    self._frames.append(data)
            except Exception as e:
                read_errors += 1
                self._notify_error("Recording error", f"Audio read failed: {e}")
                self.log_exception("audio read")
                break

        # Snapshot frames under the lock, then release
        with self._lock:
            frames = list(self._frames)
            self._frames = []

        # Close the stream
        try:
            stream.stop_stream()
            stream.close()
        except Exception:
            pass

        t_elapsed = time.time() - t_start
        self.log(f"_record_audio: loop done — {len(frames)} frames, "
                 f"{t_elapsed:.3f}s, {read_errors} errors, _recording={self.is_recording}")

        queued = self._process_frames(frames, use_large_model, keep_punctuation)
        self.log(f"_record_audio: _process_frames returned queued={queued}")
        if not queued:
            # Nothing was queued for transcription (no frames, too short, or WAV error).
            # Fire on_transcription_done so the Swift side recovers from .recording state.
            self.log("_record_audio: nothing queued — firing TRANSCRIPTION_DONE for recovery")
            self._signal_done_if_needed()

    def _signal_done_if_needed(self):
        """Fire on_transcription_done if set (used for early-exit paths)."""
        if self._on_transcription_done:
            self.log_debug("[callback] Firing on_transcription_done (early exit)")
            try:
                self._on_transcription_done()
            except Exception:
                self.log_exception("on_transcription_done callback")

    # -------------------------------------------------------- frame handling
    def _process_frames(self, frames, use_large_model, keep_punctuation):
        """Save captured frames to a WAV and enqueue for transcription.

        Returns True if work was queued, False otherwise.
        """
        if not frames:
            self.log_debug("[frames] No frames captured — nothing to process")
            return False

        duration = (len(frames) * CHUNK) / RATE

        if self.debug:
            total_bytes = sum(len(f) for f in frames)
            self.log_debug(f"[frames] {len(frames)} frames, {total_bytes} bytes, "
                           f"duration={duration:.3f}s")

        if duration <= 0.2:
            self.log(f"Recording too short ({duration:.2f}s). Skipping.")
            if self.debug:
                self.log_debug(f"[frames] Rejected: {duration:.3f}s <= 0.2s minimum")
            return False

        # Pad very short recordings to 1.5s (whisper minimum).
        # Only pad at end — front-padding creates silence that triggers
        # hallucinated YouTube phrases ("Thanks for watching", etc.)
        if duration < 1.5:
            pad_samples = int((1.5 - duration) * RATE)
            if self.debug:
                pad_bytes = pad_samples * 2  # 16-bit = 2 bytes/sample
                self.log_debug(f"[frames] Padding: {duration:.3f}s < 1.5s, "
                               f"adding {pad_samples} samples ({pad_bytes} bytes) at end")
            silence = np.zeros(pad_samples, dtype=np.int16).tobytes()
            frames.append(silence)

        fname = os.path.join(
            self.recordings_folder,
            f"recording_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.wav",
        )
        try:
            audio = self._get_audio()
            sample_width = audio.get_sample_size(FORMAT)
            if self.debug:
                self.log_debug(f"[frames] Writing WAV: {fname} "
                               f"(channels={CHANNELS}, sample_width={sample_width}, rate={RATE})")
            with wave.open(fname, "wb") as f:
                f.setnchannels(CHANNELS)
                f.setsampwidth(sample_width)
                f.setframerate(RATE)
                f.writeframes(b"".join(frames))
        except Exception as e:
            self._notify_error("Recording failed", f"Could not save audio: {e}")
            self.log_exception("write WAV")
            return False

        padded_duration = (len(frames) * CHUNK) / RATE
        self.log(f"Saved: {fname} ({duration:.2f}s, padded to {padded_duration:.2f}s)")

        if self.debug:
            file_size = os.path.getsize(fname)
            self.log_debug(f"[frames] WAV file size: {file_size} bytes")
            self.log_debug(f"[frames] Enqueuing for transcription "
                           f"(queue depth before: {self._audio_queue.qsize()})")

        self._audio_queue.put((fname, padded_duration, use_large_model, keep_punctuation))
        return True

    # ------------------------------------------------------- transcription
    def _select_model(self, duration, use_large_model):
        """Pick the right model based on duration and user request."""
        if use_large_model:
            self.log_debug("[model] Large model requested by user -> large-v3-turbo")
            return "large-v3-turbo"
        for model, cutoff in self.models.items():
            if cutoff is None:
                if self.debug:
                    self.log_debug(f"[model] Skipping {model} (manual-only, cutoff=None)")
                continue
            if self.debug:
                self.log_debug(f"[model] Checking {model}: range=[{cutoff[0]}, {cutoff[1]}], "
                               f"duration={duration:.2f}s, "
                               f"match={cutoff[0] <= duration <= cutoff[1]}")
            if cutoff[0] <= duration <= cutoff[1]:
                if self.debug:
                    self.log_debug(f"[model] Selected: {model}")
                return model
        if self.debug:
            self.log_debug(f"[model] No model matched duration {duration:.2f}s")
        return None

    def _transcription_loop(self):
        """Background worker: dequeue audio files, transcribe, paste."""
        self.log_debug("[transcribe] Transcription loop started, waiting for items...")
        while True:
            try:
                fname, duration, use_large_model, keep_punctuation = (
                    self._audio_queue.get()
                )
                t0 = time.time()

                if self.debug:
                    self.log_debug(f"[transcribe] Dequeued: {os.path.basename(fname)}, "
                                   f"duration={duration:.2f}s, large={use_large_model}, "
                                   f"keep_punct={keep_punctuation}")

                if self._on_transcribing:
                    self.log_debug("[callback] Firing on_transcribing")
                    try:
                        self._on_transcribing()
                    except Exception:
                        self.log_exception("on_transcribing callback")

                model = self._select_model(duration, use_large_model)
                if model is None:
                    self._notify_error(
                        "Transcription failed",
                        f"No model found for duration {duration:.2f}s",
                    )
                    self._signal_done_if_needed()
                    continue

                model_path = os.path.join(
                    self.whispercpp_folder, "models", f"ggml-{model}.bin"
                )
                if not os.path.exists(model_path):
                    self._notify_error(
                        "Model not found",
                        f"Missing model file: {model_path}",
                    )
                    self._signal_done_if_needed()
                    continue

                if self.debug:
                    model_size = os.path.getsize(model_path)
                    self.log_debug(f"[transcribe] Model file: {model_path} ({model_size / 1e6:.1f} MB)")

                self.log(f"Transcribing with model {model}...")
                cmd = [
                    os.path.join(self.whispercpp_folder, "main"),
                    "-m", model_path,
                    "-f", fname,
                    "--prompt", self.prompt,
                    "-nt",       # no timestamps (biggest hallucination reducer)
                    "-otxt",
                ]
                # Append version-detected anti-hallucination flags
                cmd.extend(self._extra_flags)

                if self.debug:
                    self.log_debug(f"[transcribe] Command: {shlex.join(cmd)}")
                    t_sub = time.time()

                result = subprocess.run(
                    cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
                )
                stderr_text = result.stderr.decode("utf-8", errors="ignore")

                if self.debug:
                    t_sub_elapsed = time.time() - t_sub
                    stdout_text = result.stdout.decode("utf-8", errors="ignore")
                    self.log_debug(f"[transcribe] Subprocess finished in {t_sub_elapsed:.3f}s, "
                                   f"exit code={result.returncode}")
                    self.log_debug(f"[transcribe] stdout ({len(stdout_text)} bytes): "
                                   f"'{stdout_text[:200]}{'...' if len(stdout_text) > 200 else ''}'")
                    if stderr_text.strip():
                        self.log_debug(f"[transcribe] stderr ({len(stderr_text)} bytes): "
                                       f"{stderr_text.strip()[:500]}")
                elif stderr_text.strip():
                    pass  # non-debug: stderr only logged on failure below

                if result.returncode != 0:
                    self._notify_error(
                        "Transcription failed",
                        f"whisper.cpp exited with code {result.returncode}",
                    )
                    self.log(f"stderr: {stderr_text}")
                    self._cleanup(fname, fname + ".txt")
                    self._signal_done_if_needed()
                    continue

                output_file = fname + ".txt"
                if not os.path.exists(output_file):
                    self._notify_error(
                        "Transcription failed",
                        f"Output file not found: {output_file}",
                    )
                    self._signal_done_if_needed()
                    continue

                with open(output_file) as f:
                    transcription = f.read()

                if self.debug:
                    output_size = os.path.getsize(output_file)
                    self.log_debug(f"[transcribe] Output file: {output_size} bytes, "
                                   f"{len(transcription)} chars")

                elapsed = time.time() - t0
                self.log(
                    f"Audio: {duration:.2f}s, Transcription: {elapsed:.2f}s, "
                    f"Speedup: {duration / elapsed:.2f}x"
                )

                self.log(f"Raw: '{transcription}'")
                if self.debug:
                    self.log_debug("[clean] Starting text cleaning pipeline...")
                transcription = clean_transcription(
                    transcription, keep_punctuation,
                    debug_log=self.log_debug if self.debug else None,
                )
                self.log(f"Cleaned: '{transcription}'")
                if self.debug:
                    self.log_debug(f"[clean] Final length: {len(transcription)} chars")

                if "cancel that" in transcription.lower():
                    self.log("Contains 'cancel that' — skipping.")
                    self._cleanup(fname, output_file)
                    if self._on_transcription_done:
                        self.log_debug("[callback] Firing on_transcription_done (cancel)")
                        try:
                            self._on_transcription_done()
                        except Exception:
                            self.log_exception("on_transcription_done callback")
                    continue

                if not transcription:
                    self.log("Empty transcription — skipping.")
                    self.log_debug("[transcribe] Transcription was empty after cleaning")
                elif re.fullmatch(r"[\(\*].*[\)\*]", transcription):
                    self.log(
                        f"Enclosed in brackets/asterisks — skipping: '{transcription}'"
                    )
                    self.log_debug("[transcribe] Matched bracketed/asterisk pattern — "
                                   "likely hallucination")
                else:
                    if transcription[-1] != " ":
                        transcription += " "
                    if keep_punctuation:
                        self.log("Keeping punctuation.")
                    self.log(f"Final: '{transcription}'")
                    if self.debug:
                        self.log_debug(f"[transcribe] Passing to paste: "
                                       f"{len(transcription)} chars, "
                                       f"repr={repr(transcription[:80])}")
                    self._paste_text(transcription)

                self._cleanup(fname, output_file)

                if self._on_transcription_done:
                    self.log_debug("[callback] Firing on_transcription_done")
                    try:
                        self._on_transcription_done()
                    except Exception:
                        self.log_exception("on_transcription_done callback")

                if self.debug:
                    total = time.time() - t0
                    self.log_debug(f"[transcribe] Total pipeline time: {total:.3f}s")

            except Exception:
                self.log_exception("transcription loop")
                self._signal_done_if_needed()

    def _paste_text(self, text):
        """Copy *text* to the clipboard and paste via Cmd+V with retry."""
        self.log(f"_paste_text: copying {len(text)} chars to clipboard")
        pyperclip.copy(text)
        self.log("Copied to clipboard.")

        # Verify clipboard contents (debug only — pyperclip.paste() spawns pbpaste)
        if self.debug:
            try:
                clipboard = pyperclip.paste()
                if clipboard == text:
                    self.log_debug("[paste] Clipboard verification: OK")
                else:
                    self.log_debug(f"[paste] Clipboard verification: MISMATCH "
                                   f"(expected {len(text)} chars, got {len(clipboard)} chars)")
            except Exception:
                self.log_debug("[paste] Clipboard verification failed")

        time.sleep(0.2)

        for attempt in range(3):
            if self.debug:
                self.log_debug(f"[paste] Cmd+V attempt {attempt + 1}/3")
            try:
                self._keyboard_controller.press(keyboard.Key.cmd)
                self._keyboard_controller.press("v")
                self._keyboard_controller.release("v")
                self._keyboard_controller.release(keyboard.Key.cmd)
                self.log("Pasted (Cmd+V).")
                return
            except Exception:
                self.log_exception(f"paste attempt {attempt + 1}")
                if attempt < 2:
                    self.log_debug("[paste] Retrying in 200ms...")
                    time.sleep(0.2)

        self._notify_error(
            "Paste failed",
            "Could not paste after 3 attempts. Text is on your clipboard — paste manually.",
        )

    def _cleanup(self, wav_path, txt_path):
        """Remove temporary WAV / TXT files when cleanup is enabled."""
        if not self.cleanup_recordings:
            self.log_debug("[cleanup] Skipping cleanup (cleanup_recordings=False)")
            return
        for path in (wav_path, txt_path):
            try:
                if os.path.exists(path):
                    if self.debug:
                        size = os.path.getsize(path)
                    os.remove(path)
                    if self.debug:
                        self.log_debug(f"[cleanup] Removed: {path} ({size} bytes)")
                else:
                    self.log_debug("[cleanup] File not found (already gone?): " + path)
            except Exception:
                self.log_exception(f"cleanup {path}")

    # ----------------------------------------------------------- lifecycle
    def start(self):
        """Start the background transcription worker thread."""
        threading.Thread(target=self._transcription_loop, daemon=True).start()
        self.log("Transcription worker started.")

    def verify_setup(self):
        """Check whisper.cpp binary, models, and probe for supported flags."""
        binary = os.path.join(self.whispercpp_folder, "main")
        self.log_debug("[setup] Checking binary: " + binary)
        if not os.path.exists(binary):
            self.log(f"ERROR: whisper.cpp binary not found at {binary}")
            self.log("Install whisper.cpp or set whispercpp_folder in ~/.whisperer/config.yaml")
            self.log("Searched paths: $WHISPER_CPP_PATH, ~/Documents/GitHub/whisper.cpp, ~/whisper.cpp, /opt/whisper.cpp, /usr/local/whisper.cpp")
            return False

        if self.debug:
            binary_size = os.path.getsize(binary)
            self.log_debug(f"[setup] Binary found: {binary} ({binary_size / 1e6:.1f} MB)")

        models_dir = os.path.join(self.whispercpp_folder, "models")
        if os.path.exists(models_dir):
            available = [
                f
                for f in os.listdir(models_dir)
                if f.startswith("ggml-") and f.endswith(".bin")
            ]
            self.log(f"Available models: {available}")
            if self.debug:
                all_files = os.listdir(models_dir)
                self.log_debug(f"[setup] Models dir has {len(all_files)} total files, "
                               f"{len(available)} model files")
                for m in available:
                    mpath = os.path.join(models_dir, m)
                    msize = os.path.getsize(mpath)
                    self.log_debug(f"[setup]   {m}: {msize / 1e6:.1f} MB")
        else:
            self.log(f"WARNING: Models directory not found: {models_dir}")

        # Probe whisper.cpp --help for supported anti-hallucination flags
        self._extra_flags = []
        self.log_debug("[setup] Probing whisper.cpp --help for supported flags...")
        try:
            help_result = subprocess.run(
                [binary, "--help"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            help_text = (
                help_result.stdout.decode("utf-8", errors="ignore")
                + help_result.stderr.decode("utf-8", errors="ignore")
            )
            if self.debug:
                self.log_debug(f"[setup] --help returned {len(help_text)} chars "
                               f"(exit code={help_result.returncode})")
            for flag_args, flag_name in _OPTIONAL_FLAGS:
                if flag_name in help_text:
                    self._extra_flags.extend(flag_args)
                    self.log(f"  flag supported: {' '.join(flag_args)}")
                else:
                    self.log(f"  flag NOT supported (skipping): {flag_name}")
        except subprocess.TimeoutExpired:
            self.log("[setup] whisper.cpp --help timed out after 5s")
        except Exception as e:
            self.log(f"Could not probe whisper.cpp flags: {e}")

        if self.debug:
            self.log_debug(f"[setup] Final extra flags: {self._extra_flags}")
            for name, path in [("start", _SOUND_START), ("stop", _SOUND_STOP),
                               ("error", _SOUND_ERROR)]:
                exists = os.path.exists(path)
                self.log_debug(f"[setup] Sound '{name}': {path} "
                               f"-> {'found' if exists else 'MISSING'}")

        return True


# ---------------------------------------------------------------------------
# Standard hotkey listener
# ---------------------------------------------------------------------------
def run_hotkey_listener(core):
    """Block forever, listening for the standard Whisperer hotkey combos.

    - Right Cmd + Right Option  → record and transcribe
    - + Left Cmd                → use the large model
    - + Left Option             → keep punctuation
    """
    cmd_pressed = False
    option_pressed = False
    left_cmd_pressed = False
    left_option_pressed = False

    def on_press(key):
        nonlocal cmd_pressed, option_pressed, left_cmd_pressed, left_option_pressed

        if core.debug:
            core.log_debug(f"[hotkey] PRESS {key}")

        if key == keyboard.Key.cmd_r:
            cmd_pressed = True
        elif key == keyboard.Key.alt_r:
            option_pressed = True
        elif key in (keyboard.Key.cmd_l, keyboard.Key.cmd):
            left_cmd_pressed = True
        elif key in (keyboard.Key.alt_l, keyboard.Key.alt):
            left_option_pressed = True

        if core.debug:
            core.log_debug(f"[hotkey] State: cmd={cmd_pressed} opt={option_pressed} "
                           f"lcmd={left_cmd_pressed} lopt={left_option_pressed} "
                           f"recording={core.is_recording}")

        if cmd_pressed and option_pressed and not core.is_recording:
            use_large = left_cmd_pressed
            keep_punct = left_option_pressed
            msg = "Starting recording"
            if use_large:
                msg += " with large model"
            if keep_punct:
                msg += " (keeping punctuation)"
            core.log(msg + "...")
            core.start_recording(
                use_large_model=use_large, keep_punctuation=keep_punct
            )

    def on_release(key):
        nonlocal cmd_pressed, option_pressed, left_cmd_pressed, left_option_pressed

        if core.debug:
            core.log_debug(f"[hotkey] RELEASE {key}")

        if key == keyboard.Key.cmd_r:
            cmd_pressed = False
        elif key == keyboard.Key.alt_r:
            option_pressed = False
        elif key in (keyboard.Key.cmd_l, keyboard.Key.cmd):
            left_cmd_pressed = False
        elif key in (keyboard.Key.alt_l, keyboard.Key.alt):
            left_option_pressed = False

        if core.debug:
            core.log_debug(f"[hotkey] State: cmd={cmd_pressed} opt={option_pressed} "
                           f"lcmd={left_cmd_pressed} lopt={left_option_pressed} "
                           f"recording={core.is_recording}")

        if core.is_recording and (not cmd_pressed or not option_pressed):
            core.log_debug("[hotkey] Trigger key released — stopping recording")
            core.stop_recording()

    core.log("Hotkeys:")
    core.log("  Right Cmd + Right Option  ->  record & transcribe")
    core.log("  + Left Cmd                ->  use large model")
    core.log("  + Left Option             ->  keep punctuation")

    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        core.log("Listening...")
        listener.join()
