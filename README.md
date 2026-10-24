# Dictate — macOS Voice Dictation

A menu-bar app that converts speech to text and pastes it into whatever you're typing in. All processing runs locally — audio never leaves your Mac.

## Features

- **Toggle recording** — press to start, press to stop (no holding)
- **Floating waveform overlay** — 9 animated bars, dark/light adapted
- **Two model backends** — Whisper (484MB, fine-tuned) or Whistle (16MB, CPU-only)
- **Voice commands** — say "my email" → inserts your email address
- **Text replacements** — word-level rules (e.g., "cloud code" → "Claude Code")
- **Silence auto-stop** — stops recording after configurable silence
- **Correction learning** — auto-detects edits after pasting, suggests replacements
- **Press/release sounds** — 9 futuristic packs with live preview
- **Auto-press Enter** — optional, for chat/messaging apps
- **Escape to discard** — discard a recording mid-flight
- **Audio saving** — opt-in, for future model training

## Requirements

- macOS 13+ (Ventura or later)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.10+ with pip
- (Whisper only) ~500MB disk for model + ~2GB RAM
- (Whistle only) ~20MB disk, ~30MB RAM

## Quick Start

### 1. Clone and build

```bash
git clone https://github.com/rajualankar2-stack/dictate-app.git
cd dictate-app
bash scripts/build_app.sh
open build/Dictate.app
```

### 2. Install Python dependencies

**For Whisper (default, higher accuracy):**
```bash
pip install transformers torch peft
```

**For Whistle (lighter, faster):**
```bash
pip install cactus-needle
```

### 3. Start the transcription server

**Whisper:**
```bash
cd server
python3 dictate_srv.py start
```

**Whistle:**
```bash
cd server
python3 whistle_srv.py start
```

### 4. Grant permissions

On first launch, macOS will ask for:
- **Microphone** — for recording
- **Accessibility** — for pasting text (System Settings → Privacy & Security → Accessibility)

### 5. Configure

Open Settings (menu bar icon → Settings):
- **General** — sounds, animation, auto-Enter
- **Words** — vocabulary, replacements, voice commands
- **Dictation** — silence threshold, model backend, server location
- **Status** — permissions, engine status

## Privacy

- All audio processing happens on your Mac
- Server runs on 127.0.0.1 only (config validator rejects non-localhost URLs)
- Audio saving is opt-in (off by default)
- No data is sent to any cloud service

## Project Structure

```
dictate-app/
├── Sources/Dictate/          # macOS app (SwiftUI + AppKit)
├── Sources/DictateCore/      # Shared logic (config, controller, words)
├── server/                   # Python transcription servers
│   ├── dictate_srv.py        # Whisper + LoRA
│   └── whistle_srv.py        # Whistle (16MB)
├── Resources/Sounds/         # Sound packs
├── scripts/                  # Build and test scripts
└── Tests/                    # Unit tests
```

## License

MIT
