# meeting-copilot

Live meeting transcription copilot for pi. Captures audio on your Mac via whisper-cpp, streams the transcript to your dev machine, and gives pi real-time meeting context.

## When to Use

Use when the user:
- Starts a meeting and wants live transcription
- Says "start transcribing", "I'm in a meeting", or "tail the transcript"
- Asks for meeting notes or a summary after a call
- Wants to ask questions about what was discussed

## Tools

### meeting_copilot

| Action | Description |
|--------|-------------|
| `start` | Begin tracking a transcript file (default: `/tmp/live-transcript.txt`) |
| `stop` | Stop tracking |
| `status` | Show current state — recording, file path, lines read |
| `read_new` | Read only new lines since last check (incremental) |
| `read_all` | Read the entire transcript |

### Commands

- `/meeting start` — Start the copilot
- `/meeting stop` — Stop and summarize
- `/meeting status` — Check state

## Workflow

1. User starts transcription on their Mac (menu bar app or CLI — see setup docs)
2. Transcript syncs to dev machine at `/tmp/live-transcript.txt`
3. Use `meeting_copilot start` to begin tracking
4. Periodically use `read_new` to get incremental updates
5. At end of meeting, use `read_all` to get full transcript for summarization

## Configuration

Set `MEETING_TRANSCRIPT_PATH` env var to change the default transcript location.
