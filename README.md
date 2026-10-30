<div align="center">

<img src="docs/icon.png" width="128" alt="Dictate app icon">

# Dictate

**Talk, and the text lands wherever your cursor is.**
A macOS menu-bar dictation app. All transcription runs locally, so your audio never leaves your Mac.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![Python 3.10+](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)
![100% local](https://img.shields.io/badge/audio-100%25%20local-2ea44f)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

</div>

## 🎬 See it in action

https://github.com/user-attachments/assets/3ec8319d-ad5d-459f-97f2-c1e4ac40beab

## ✨ Features

| | Feature | What it does |
|---|---|---|
| 🎙️ | **Toggle recording** | Press to start, press again to stop. No holding a key down. |
| 🌊 | **Floating waveform** | Nine animated bars that adapt to dark and light mode |
| 🧠 | **On-device speech model** | Parakeet Unified EN 0.6B, under 0.1 s per clip, audio never leaves the Mac |
| 🔠 | **Text style** | Normal, lowercase, UPPERCASE or random case, plus optional removal of the trailing period |
| 👋 | **Welcome tour** | First launch walks through permissions and a practice dictation |
| 🗣️ | **Voice commands** | Say "my email" and it inserts your email address |
| 🔁 | **Text replacements** | Word-level rules, e.g. "cloud code" → "Claude Code" |
| 🤫 | **Silence auto-stop** | Stops recording after a configurable pause |
| 📚 | **Correction learning** | Notices your edits after a paste and suggests replacements |
| 🔊 | **Sound packs** | 9 futuristic press and release sound packs with live preview |
| ↩️ | **Auto-press Enter** | Optional, for chat and messaging apps |
| ⎋ | **Escape to discard** | Throw away a recording mid-flight |
| 💾 | **Audio saving** | Opt-in, for future model training |

## 🔒 Privacy

- All audio processing happens on your Mac
- The server listens on `127.0.0.1` only (the config validator rejects non-localhost URLs)
- Audio saving is opt-in and off by default
- No data is sent to any cloud service

## 📋 Requirements

- macOS 14+ (Sonoma or later)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.10+ (macOS ships 3.9, so `brew install python@3.11` if needed)
- Parakeet: about 731 MB disk for the model and about 1 GB RAM while it runs (it stops after 10 idle minutes)

## 🚀 Quick start

### 1. Clone, set up and build

Clone anywhere you like, and keep the folder: the app runs its server from it.

```bash
git clone https://github.com/rajualankar2-stack/dictate-app.git
cd dictate-app
bash scripts/setup.sh       # creates .venv and downloads the Parakeet model (731 MB, once)
bash scripts/build_app.sh
open build/Dictate.app
```

The app starts the transcription server itself on the first key press. For the lighter Whistle backend, also run `.venv/bin/pip install cactus-needle` and pick Whistle under Settings → Dictation.

Nothing else needs to be installed: the speech engine (`transcribe-cpp`, Metal) runs inside the app's own Python.

### 2. Signing

`build_app.sh` signs with your Apple Development certificate if you have one. Without one it signs ad-hoc, which works, but macOS treats every rebuild as a new app, so you have to grant Accessibility again after each rebuild.

### 3. Grant permissions

On first launch, macOS asks for:

- **Microphone**, for recording
- **Accessibility**, for pasting text (System Settings → Privacy & Security → Accessibility)

### 4. Configure

Open Settings from the menu bar icon:

| Tab | Settings |
|---|---|
| **General** | Sounds, animation, auto-Enter |
| **Words** | Vocabulary, replacements, voice commands |
| **Dictation** | Silence threshold, model backend, server location |
| **Status** | Permissions, engine status |

## 🗂️ Project structure

```
dictate-app/
├── Sources/Dictate/          # macOS app (SwiftUI + AppKit)
├── Sources/DictateCore/      # Shared logic (config, controller, words)
├── server/                   # Python transcription servers
│   ├── parakeet_srv.py       # Parakeet via transcribe.cpp (default)
│   └── stt_common.py         # SAP word fixes, audio preparation
├── Resources/Sounds/         # Sound packs
├── scripts/                  # Build and test scripts
└── Tests/                    # Unit tests
```

## 📄 License

MIT
