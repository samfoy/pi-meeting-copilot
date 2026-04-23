# pi-meeting-copilot

Live meeting transcription copilot for [pi](https://github.com/mariozechner/pi-coding-agent). Tracks a transcript file in real time, giving pi meeting context for questions, note-taking, and summarization.

## Install

```bash
pi install git:github.com/samfoy/pi-meeting-copilot
```

This gives you:
- `meeting_copilot` tool — start/stop tracking, read incremental updates, read full transcript
- `/meeting` command — quick shortcuts for start/stop/status
- Skill file so the LLM knows when and how to use it

## Usage

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

## Feeding It a Transcript

The extension reads a plain text file that grows over time — one line per utterance. It doesn't capture audio itself. Anything that appends text to a file works.

**Default path:** `/tmp/live-transcript.txt`

Override with `MEETING_TRANSCRIPT_PATH` env var or pass `path` to the tool.

### Example Sources

**whisper.cpp** (local, Mac/Linux — best for real-time):
```bash
brew install whisper-cpp blackhole-2ch  # macOS
whisper-stream --model ~/.whisper-models/ggml-medium.en.bin \
  --capture 0 --file /tmp/live-transcript.txt \
  --step 5000 --length 10000 --vad-thold 0.8
```
Use [BlackHole](https://github.com/ExistentialAudio/BlackHole) to route system audio (Zoom, Meet, etc.) to whisper as input.

**Otter.ai / Zoom / Teams** (cloud transcription):
Export or copy the transcript to a file. For live use, some tools let you sync captions to a local file.

**Any speech-to-text CLI** that writes to stdout:
```bash
my-stt-tool --input mic >> /tmp/live-transcript.txt
```

**Remote machine?** If your transcription runs on a laptop but pi runs on a remote dev box, sync the file:
```bash
# From laptop, sync every 3 seconds
watch -n3 scp ~/transcript.txt devbox:/tmp/live-transcript.txt

# Or stream it
tail -f ~/transcript.txt | ssh devbox "cat >> /tmp/live-transcript.txt"
```

### Format

No special format required. The copilot reads plain text, one line at a time. Timestamps are nice but optional:

```
[09:01:15] Let's start with the status update
[09:01:22] The deploy went out yesterday, no issues
we can also handle lines without timestamps
```

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `MEETING_TRANSCRIPT_PATH` | `/tmp/live-transcript.txt` | Where pi reads the transcript |

## How It Works

1. A transcription source appends lines to a text file
2. `meeting_copilot` tracks your read position — `read_new` returns only lines since your last check
3. State persists across pi turns via session entries, so position survives context compaction
4. At meeting end, `read_all` gets the full transcript for summarization

## Files

```
pi-meeting-copilot/
├── package.json              # Pi package manifest
├── src/
│   └── index.ts              # Extension — meeting_copilot tool + /meeting command
└── skills/
    └── meeting-copilot/
        └── SKILL.md          # Skill file for LLM context
```

## License

MIT
