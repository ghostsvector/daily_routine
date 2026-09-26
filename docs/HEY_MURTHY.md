# "Hey Murthy" — voice assistant / professor

What "Ask Murthy" (typed) and "Hey Murthy" (spoken) actually are, why each
piece is built the way it is, and what's still rough. Written in the same
spirit as `ARCHITECTURE.md`: the "why," not just the "what," for whoever
picks this up next — including future-you.

Not to be confused with the existing, unrelated "Murthy" feature
(`lib/features/murthy/` — an encrypted daily-protocol/progress tracker,
see `ARCHITECTURE.md`'s layer 3). Same name, deliberately kept — see
"Why the name collision was kept," below.

## What it does

Type (or say) a topic you've forgotten — "what is a transformer neural
network," "న్యూటన్ మూడో నియమం అంటే ఏమిటి" — and Murthy explains it from a
local LLM's own pretrained knowledge, then speaks the explanation aloud in
whichever language you asked in. Say "Hey Murthy" first and it's
hands-free: wake word → your question → spoken answer, no typing.

No cloud AI API, no per-request cost, no account beyond what's needed to
train the wake-word model once (see below). Everything — the LLM, the
voices, the wake word, the speech-to-text — runs on the device.

## The ecosystem, extended

`ARCHITECTURE.md` lists four repos. This feature adds a fifth:

| Repo | What it is | Why separate |
|---|---|---|
| [`murthy-voice`](https://github.com/ghostsvector/murthy-voice) | The actual model/voice code: Python scripts wrapping an LLM and two TTS voices, plus a wake-word + speech-to-text pipeline | Needed its own venv, its own heavy CPU-ML dependencies (`torch`, `transformers`, `llama-cpp-python`, `openwakeword`, `faster-whisper`) that have nothing to do with Flutter — and needed to be iterated on/A-B-tested as a standalone terminal tool *before* any app integration existed |

## Layer by layer

### 1. The brain and voices (`murthy-voice`, Python, Linux-desktop-native)

- **LLM** — [Qwen3-1.7B](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF)
  (Apache-2.0, GGUF, ~1.1GB), run via `llama-cpp-python`, CPU-only
  (`llm.py`).
- **TTS** — Telugu + English, both via Meta's
  [MMS](https://huggingface.co/facebook/mms-tts-tel) VITS models through
  `transformers`/PyTorch, CPU-only (`tts.py`).
- **Wake word + STT** — [openWakeWord](https://github.com/dscripka/openWakeWord)
  for "Hey Murthy" detection, [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
  for transcribing what you say after it, both CPU-only, combined into one
  microphone-owning loop (`voice_trigger_server.py`).

**Why Qwen3, not DeepSeek or Kimi**: researched at the time — Kimi (K2
through K3) and DeepSeek's V3/R1/V4 lines are all huge Mixture-of-Experts
models (hundreds of billions to trillions of params) meant for datacenter
serving, not an option for CPU-only local inference at all. DeepSeek's
small *distilled* checkpoints (1.5B+) do run on CPU, but they're distilled
from a reasoning model and tend to emit visible chain-of-thought, which
reads badly out loud. Qwen3 is the family that goes genuinely small
(0.6B/1.7B/4B dense) while staying coherent enough to explain a topic —
1.7B was picked as the quality/speed balance; see `murthy-voice`'s README
for how to swap in `Qwen3-0.6B` (low-RAM) or `Qwen3-4B` (more RAM,
noticeably better) instead.

**Why these are terminal/subprocess scripts, not a library**: this project
started as (and still is) a standalone experiment — voice/model choice
needed to be A-B-tested via `murthy_assistant.py` before any app
integration was worth building. The app integration (next section) drives
the *same* scripts as subprocesses rather than reimplementing any of this
logic a second time in Dart.

**No custom "Hey Murthy" wake-word model ships in the repo.** Training one
needs either a GPU or a long CPU run — not something to do inside an
automated coding session. Until it's trained, `voice_trigger_server.py`
falls back to openWakeWord's bundled `hey_jarvis` model (say "hey jarvis"
instead) so the rest of the pipeline is testable. `murthy-voice`'s README
has two training paths: a hosted service
([openwakeword.com/train](https://openwakeword.com/train)) or a local
Piper-TTS-based pipeline, CPU-feasible but slow without a GPU.

### 2. The SDK contract (`daily_routine_sdk`, `lib/assistant/`)

Three interfaces, following the same pattern as every other SDK service
(abstract interface + swappable implementations, `Result<T>`/`AppError`
for failures — see `ARCHITECTURE.md` layer 2):

- `AssistantService.explain(topic)` → spoken-friendly explanation text
- `VoiceService.speak(text, languageCode:)` → speaks it
- `WakeWordService.events` → a `Stream` of `WakeDetected` →
  `QueryTranscribed(text)` (or `WakeWordError`)

Two implementation sets, one per platform that actually has one:

**Linux desktop** (`LinuxProcess*Service`, three classes) — each spawns
the matching `murthy-voice` script (`assistant_server.py`,
`tts_server.py`, `voice_trigger_server.py`) as a **subprocess** and talks
to it over stdin/stdout: request/response as one-JSON-object-per-line for
the assistant/voice ones, a push stream of JSON events for the wake-word
one. No network socket anywhere — just a pipe this Dart code owns.
Configured once via `MurthyAssistantConfig.configure()` (a Python
executable path + a `murthy-voice` clone path — see "Local setup" below).

**Why a subprocess, not a native/FFI binding, on Linux**: binding
`llama.cpp` directly into the Dart binary would need a compiled
`libllama` with no prebuilt binary available for Linux — not something to
attempt without being able to build and test it. A subprocess reuses the
exact model/TTS/wake-word code already proven to work in `murthy-voice`,
at the cost of Linux-desktop-only (no Android Python runtime to spawn).

**Android** (`AndroidLlamaAssistantService`, `FlutterTtsVoiceService`,
`AndroidSpeechWakeWordService`) — a genuinely different, native-ish path,
since there's no Python to shell out to:

- `AndroidLlamaAssistantService` runs the *same* Qwen3-1.7B model
  on-device via [`llama_cpp_dart`](https://pub.dev/packages/llama_cpp_dart)
  (`LlamaParent`/`LlamaLoad`), downloading the model into app support
  storage on first use (~1.1GB, no Wi-Fi-only gating yet).
- `FlutterTtsVoiceService` uses the OS's own TTS engine instead of the
  Telugu/English MMS voices — there's no Python runtime to run those
  through.
- `AndroidSpeechWakeWordService` **approximates** "Hey Murthy": there is
  no Android/Flutter binding for openWakeWord at all, so instead it runs
  the OS's own speech recognizer (`speech_to_text`) continuously and
  watches for "murthy" in what it hears, then listens again for the
  actual question. This costs meaningfully more battery than a real
  always-on keyword-spotting model would — a known, accepted limitation,
  not an oversight.

**Why both `llama_cpp_dart` and `speech_to_text` needed source-level
verification, not just doc-reading**: both packages' README/doc-comment
examples turned out to lag their actual published API (breaking changes
landed without the docs catching up). Guessing from docs alone produced
code that failed CI's `flutter analyze` outright (undefined classes,
deprecated-param lints) on the first two attempts. The fix each time was
downloading the exact resolved package version's `.tar.gz` from pub.dev's
own archive API and reading the real source — see the `daily_routine_sdk`
PR history for both incidents. Lesson generalized: for any actively-changing
third-party package with no compiler available to verify against, read
the real installed source before writing integration code, not the docs.

### 3. The app UI (`daily_routine`, `lib/features/murthy/`)

`AskMurthySection` (a card on the existing Murthy screen — yes, that
Murthy, see the name-collision note above) with a text field + Explain
button, plus a mic toggle. Tapping the mic calls `WakeWordService.start()`
and subscribes to its event stream: `WakeDetected` updates the UI copy to
"listening for your question," `QueryTranscribed` feeds straight into the
same `_ask()` path typing would, `WakeWordError` surfaces the message and
keeps listening.

`murthyAssistantAvailableProvider` decides whether the section renders at
all: unconditionally `true` on Android (self-contained, downloads its own
model); on Linux, only once `MurthyAssistantConfig.isConfigured` (i.e.
the two `.env` vars below are set); `false` everywhere else — no
iOS/macOS/Windows implementation exists.

## Local setup (Linux desktop)

```bash
git clone https://github.com/ghostsvector/murthy-voice
cd murthy-voice
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python download_model.py   # ~1.1GB, one-time
```

Then in `daily_routine`'s `.env` or `.env.local`:

```
MURTHY_PYTHON_EXECUTABLE=/path/to/murthy-voice/venv/bin/python
MURTHY_VOICE_REPO_PATH=/path/to/murthy-voice
```

Android needs no setup — it downloads its own model on first use.

## Why the name collision was kept

`daily_routine` already had an unrelated "Murthy" feature (an encrypted
daily-protocol/progress tracker) before this one existed. Renaming the
new voice feature to avoid the collision was considered and explicitly
rejected — kept as "Murthy" for both, distinguished entirely by file/class
names underneath (`AskMurthySection` vs. `MurthyScreen`/`MurthyRepository`)
rather than by product naming. If this becomes confusing in practice,
that's the lever to pull, not a name found by searching for one that
happened to avoid a clash today.

## Known limitations (not yet solved, not being actively worked)

- **No trained "Hey Murthy" wake-word model** — falls back to `hey_jarvis`
  on Linux; see `murthy-voice`'s README for the two training paths.
- **`AndroidSpeechWakeWordService` isn't a real wake-word engine** —
  continuous speech recognition standing in for one, meaningfully worse
  on battery. The real fix (a wake-word engine with an Android/Flutter
  binding) doesn't exist for openWakeWord; would need either a different
  engine (e.g. Picovoice Porcupine, which has one but requires a
  Picovoice account/API key and has free-tier usage limits — considered,
  not chosen, when this was scoped) or a custom native binding.
- **No Wi-Fi-only gating on Android's ~1.1GB model download.** Worth
  adding before this ships to real users; not done here.
- **`AndroidLlamaAssistantService` and `AndroidSpeechWakeWordService` are
  unbuilt on a real device** — their Dart-level API usage is verified
  against real published package source, but no Flutter/Android
  toolchain was available to actually build and run an APK while writing
  this. First real-device run is still outstanding verification, not an
  assumption to trust blindly.
- **No iOS/macOS/Windows implementation** of any of the three services.
- **Video mode and news** (a talking avatar, or fetch+summarize+speak)
  were both scoped in `murthy-voice`'s README and deliberately deferred —
  audio-first until this foundation was solid.
- **No grounding in personal notes/textbooks.** Murthy only knows what
  Qwen3-1.7B was pretrained on — no RAG, no fine-tuning. Deliberately
  skipped: prompting the pretrained model directly was enough to get a
  working "explain this topic" loop, and RAG/fine-tuning is real
  additional scope for a fairly marginal quality gain on top of that.

## Next plans

Nothing here is committed — same caveat as `ARCHITECTURE.md`'s own list:

1. **Train the real "Hey Murthy" wake-word model** — the one piece that
   turns this from "works if you say hey jarvis" into the actual feature
   as designed.
2. **First real Android build/run** — confirm `llama_cpp_dart` and
   `speech_to_text` behave as their source suggested, fix whatever
   doesn't survive contact with a real device.
3. **Wi-Fi-only gating** for Android's model download, before wider use.
4. **A real Android wake-word engine**, if the continuous-recognition
   approximation's battery cost turns out to matter in practice.
