# "Hey Murthy" wake-word models (ONNX / openWakeWord)

No account or paid access key needed for this path — it's built on
[openWakeWord](https://github.com/dscripka/openWakeWord), an open-source
wake-word engine, run locally via ONNX Runtime. Three model files go in
this folder, and unlike the previous Picovoice approach these are the
*same file on every platform* — ONNX Runtime loads them directly from
asset bytes, no per-platform training or file naming needed.

1. **`melspectrogram.onnx`** and **`embedding_model.onnx`** — generic,
   shared by every openWakeWord keyword, not specific to "Hey Murthy".
   Download them once from openWakeWord's GitHub releases:
   https://github.com/dscripka/openWakeWord/releases (look for
   `melspectrogram.onnx` and `embedding_model.onnx` in the release
   assets — they're also mirrored in the repo's `openwakeword/resources/models/`
   directory if a given release doesn't list them separately).

2. **`hey_murthy.onnx`** — the actual custom wake-word classifier. This
   one has to be trained — there's no pretrained "Hey Murthy" model
   anywhere — but training is free and doesn't need an account:
   - Open openWakeWord's training notebook,
     `notebooks/automatic_model_training.ipynb`, in Google Colab (a link
     is in the openWakeWord README).
   - Set the target phrase to `hey_murthy` and run all cells. It
     synthesizes training clips with text-to-speech + audio augmentation
     and trains a small classifier — no microphone recordings from you
     required, though the model will detect real speech better if you
     also record a few real samples of yourself saying it and add them
     to the notebook's fine-tuning step (optional).
   - Download the resulting `.onnx` file, rename it `hey_murthy.onnx`,
     and put it here.

Until all three files are present, the "Hey Murthy" toggle in the app
shows "not set up yet" instead of enabling — it won't pretend to listen.

These files aren't committed if this repo is public: `.gitignore` already
excludes everything in this folder except this README. The two generic
models are safe to share (Apache-2.0, no personal data); the custom one
isn't personal either, but there's no reason to bloat the repo with it.
