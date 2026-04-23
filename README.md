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

## Transcript Source

This extension reads a transcript file — it doesn't capture audio itself. Point any transcription tool at the file and the copilot picks it up.

Examples of what can produce the transcript:
- [whisper.cpp stream](https://github.com/ggerganov/whisper.cpp) with BlackHole audio capture
- Zoom's built-in transcription exported to a file
- Any speech-to-text tool that writes to a text file

Default path: `/tmp/live-transcript.txt`. Override with:
```bash
export MEETING_TRANSCRIPT_PATH="/path/to/transcript.txt"
```

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `MEETING_TRANSCRIPT_PATH` | `/tmp/live-transcript.txt` | Where pi reads the transcript |


## How It Works

1. A transcription tool writes meeting audio to a text file (any tool works)
2. The `meeting_copilot` tool reads that file incrementally, tracking read position across calls so you only see new content
3. At meeting end, read the full transcript and ask pi to produce structured notes, action items, and decisions

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
