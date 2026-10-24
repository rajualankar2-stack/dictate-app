<div align="center">

<img src="docs/icon.png" width="128" alt="Dictate app icon">

# Dictate

**Talk, and the text lands wherever your cursor is.**
A macOS menu-bar dictation app. All transcription runs locally, so your audio never leaves your Mac.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
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
| 🧠 | **Two model backends** | Whisper (484 MB, fine-tuned) or Whistle (16 MB, CPU only) |
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

- macOS 13+ (Ventura or later)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.10+ with pip
- Whisper: about 500 MB disk for the model and about 2 GB RAM
- Whistle: about 20 MB disk and about 30 MB RAM

## 🚀 Quick start

### 1. Clone and build

```bash
git clone https://github.com/rajualankar2-stack/dictate-app.git
cd dictate-app
bash scripts/build_app.sh
open build/Dictate.app
```

### 2. Install Python dependencies

```bash
# Whisper (default, higher accuracy)
pip install transformers torch peft

# Whistle (lighter, faster)
pip install cactus-needle
```

### 3. Start the transcription server

```bash
cd server
python3 dictate_srv.py start   # Whisper
python3 whistle_srv.py start   # or Whistle
```

### 4. Grant permissions

On first launch, macOS asks for:

- **Microphone**, for recording
- **Accessibility**, for pasting text (System Settings → Privacy & Security → Accessibility)

### 5. Configure

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
│   ├── dictate_srv.py        # Whisper + LoRA
│   └── whistle_srv.py        # Whistle (16 MB)
├── Resources/Sounds/         # Sound packs
├── scripts/                  # Build and test scripts
└── Tests/                    # Unit tests
```

## 📄 License

MIT
