# pi-meeting-copilot

Live meeting transcription copilot for [pi](https://github.com/mariozechner/pi-coding-agent). Captures audio via whisper-cpp on your Mac, streams transcripts to your dev machine, and gives pi real-time meeting context for note-taking and summarization.

```
Mac Laptop                          Dev Machine
┌─────────────────────┐    SSH/SCP   ┌──────────────────────┐
│ Zoom → BlackHole    │ ──────────► │ /tmp/live-transcript  │
│   → whisper-cpp     │             │   → pi meeting_copilot│
│   → transcript.txt  │             │   → notes & summaries │
└─────────────────────┘             └──────────────────────┘
```

## Install

```bash
pi install git:github.com/samfoy/pi-meeting-copilot
```

This gives you:
- `meeting_copilot` tool — the LLM can start/stop tracking, read incremental updates, and summarize
- `/meeting` command — quick shortcuts for start/stop/status
- Skill file so the LLM knows when and how to use the tool

## Usage in pi

```
> I'm joining a standup, start the meeting copilot
# pi calls meeting_copilot(action: "start")

> what's been discussed so far?
# pi calls meeting_copilot(action: "read_new") and summarizes

> meeting's over, give me notes
# pi calls meeting_copilot(action: "read_all") and produces structured notes
```

Or use the command shortcut:
```
/meeting start
/meeting stop
/meeting status
```

## Mac Setup (One-Time)

The extension reads a transcript file on your dev machine. You need something on your Mac to capture audio and sync it over. The `scripts/` directory has everything you need.

### 1. Install dependencies

```bash
brew install whisper-cpp blackhole-2ch
pip3 install rumps  # for menu bar app (optional)
```

### 2. Download a Whisper model

```bash
mkdir -p ~/.whisper-models
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin" \
  -o ~/.whisper-models/ggml-medium.en.bin
```

Model options: `tiny.en` (fast, lower quality), `base.en` (balanced), `medium.en` (best accuracy on Apple Silicon), `large-v3` (best, slower).

### 3. Configure audio routing

1. Open **Audio MIDI Setup** (Spotlight → "Audio MIDI Setup")
2. Click **+** → **Create Multi-Output Device**
3. Check both your speakers/headphones AND **BlackHole 2ch**
4. Rename to **"Zoom + Capture"**
5. In Zoom → Settings → Audio → Speaker → select **"Zoom + Capture"**

### 4. Start transcription

**Option A: Menu bar app** (recommended)
```bash
cd scripts/
python3 menubar.py
```
Click the 🎙️ icon → select BlackHole as audio source → Start Recording. Transcripts sync to your dev machine automatically.

**Option B: CLI**
```bash
cd scripts/
export CLOUD_DESKTOP="your-dev-machine.example.com"
./transcribe.sh start --sync
```

### 5. Configure sync target

Set your dev machine hostname:
```bash
export CLOUD_DESKTOP="your-dev-machine.example.com"
```

The transcript lands at `/tmp/live-transcript.txt` on the remote machine. Override with:
```bash
export MEETING_TRANSCRIPT_PATH="/path/to/transcript.txt"
```

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `MEETING_TRANSCRIPT_PATH` | `/tmp/live-transcript.txt` | Where pi reads the transcript |
| `CLOUD_DESKTOP` | — | SSH hostname for Mac → dev machine sync |
| `WHISPER_MODEL` | `~/.whisper-models/ggml-medium.en.bin` | Whisper model path (Mac side) |
| `CAPTURE_DEVICE` | `2` | BlackHole capture device ID (Mac side) |

## How It Works

1. **Mac side**: `whisper-cpp` captures system audio via BlackHole virtual audio device and writes timestamped transcript lines to a file
2. **Sync**: `scp` copies the transcript to your dev machine every 3 seconds
3. **Pi side**: The `meeting_copilot` tool reads the transcript file incrementally, tracking read position across calls so you only see new content
4. **Summarization**: At meeting end, read the full transcript and ask pi to produce structured notes, action items, and decisions

## Files

```
pi-meeting-copilot/
├── package.json              # Pi package manifest
├── src/
│   └── index.ts              # Extension — meeting_copilot tool + /meeting command
├── skills/
│   └── meeting-copilot/
│       └── SKILL.md          # Skill file for LLM context
└── scripts/
    ├── menubar.py            # macOS menu bar app (rumps)
    ├── transcribe.sh         # CLI transcription script
    └── tail-transcript.sh    # Simple tail wrapper
```

## License

MIT
