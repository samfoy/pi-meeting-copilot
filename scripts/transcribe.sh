#!/usr/bin/env bash
# transcribe.sh — Capture system audio via BlackHole and transcribe with whisper-cpp
#
# Usage:
#   ./transcribe.sh start [--sync]   Start transcription (--sync enables cloud desktop sync)
#   ./transcribe.sh stop             Stop transcription
#   ./transcribe.sh status           Check if running
#
# Requirements (Mac):
#   brew install whisper-cpp blackhole-2ch sox
#   Download model: see README.md

set -euo pipefail

# --- Configuration ---
WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.whisper-models/ggml-medium.en.bin}"
TRANSCRIPT_DIR="${TRANSCRIPT_DIR:-$HOME/transcripts}"
CAPTURE_DEVICE="${CAPTURE_DEVICE:-2}"  # BlackHole 2ch capture device ID
CLOUD_DESKTOP="${CLOUD_DESKTOP:-dev-dsk-samfp-2a-d82872ff.us-west-2.amazon.com}"
REMOTE_PATH="/tmp/live-transcript.txt"
SYNC_INTERVAL=3  # seconds between syncs
PIDFILE="/tmp/transcribe.pid"
SYNC_PIDFILE="/tmp/transcribe-sync.pid"

# --- Helpers ---
log() { echo "[$(date +%H:%M:%S)] $*"; }

find_blackhole_device() {
    # sox uses device index; find BlackHole's index
    # On macOS, rec uses CoreAudio device names directly via AUDIODEV
    echo "${BLACKHOLE_DEVICE}"
}

ensure_model() {
    if [[ ! -f "$WHISPER_MODEL" ]]; then
        echo "ERROR: Whisper model not found at $WHISPER_MODEL"
        echo "Download it:"
        echo "  mkdir -p ~/.whisper-models"
        echo '  curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" -o ~/.whisper-models/ggml-base.en.bin'
        exit 1
    fi
}

start_sync() {
    local transcript_file="$1"
    log "Starting sync to ${CLOUD_DESKTOP}:${REMOTE_PATH} every ${SYNC_INTERVAL}s"
    (
        while true; do
            if [[ -f "$transcript_file" ]]; then
                scp -q "$transcript_file" "${CLOUD_DESKTOP}:${REMOTE_PATH}" 2>/dev/null || true
            fi
            sleep "$SYNC_INTERVAL"
        done
    ) &
    echo $! > "$SYNC_PIDFILE"
    log "Sync PID: $(cat "$SYNC_PIDFILE")"
}

stop_sync() {
    if [[ -f "$SYNC_PIDFILE" ]]; then
        local pid
        pid=$(cat "$SYNC_PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            log "Stopped sync (PID $pid)"
        fi
        rm -f "$SYNC_PIDFILE"
    fi
}

# --- Commands ---
cmd_start() {
    local do_sync=false
    [[ "${1:-}" == "--sync" ]] && do_sync=true

    ensure_model
    mkdir -p "$TRANSCRIPT_DIR"

    local timestamp
    timestamp=$(date +%Y-%m-%d-%H%M%S)
    local transcript_file="${TRANSCRIPT_DIR}/${timestamp}.txt"
    local latest_link="${TRANSCRIPT_DIR}/latest.txt"

    # Create/update symlink
    ln -sf "$transcript_file" "$latest_link"
    touch "$transcript_file"

    log "Transcript: $transcript_file"
    log "Capture device: ${CAPTURE_DEVICE}"
    log "Model: $WHISPER_MODEL"

    # Check if whisper-stream exists (brew install whisper-cpp)
    local whisper_bin
    if command -v whisper-stream &>/dev/null; then
        whisper_bin="whisper-stream"
    elif [[ -x /opt/homebrew/bin/whisper-stream ]]; then
        whisper_bin="/opt/homebrew/bin/whisper-stream"
    else
        echo "ERROR: whisper-stream not found"
        echo "Install: brew install whisper-cpp"
        echo "Check binary name: brew list whisper-cpp | grep bin"
        exit 1
    fi

    # Start sync if requested
    if $do_sync; then
        start_sync "$transcript_file"
    fi

    # Capture audio from BlackHole via sox, pipe raw PCM to whisper-cpp-stream
    # sox rec: captures from AUDIODEV at 16kHz mono 16-bit signed integer
    # whisper-cpp-stream: reads raw audio from default capture device or stdin
    # whisper-stream captures directly from CoreAudio — no sox needed.
    # BlackHole 2ch = capture device 0 (verify with --capture 1, 2 if wrong)
    log "Starting transcription... (Ctrl+C to stop)"

    (
        "$whisper_bin" \
            --model "$WHISPER_MODEL" \
            --capture "${CAPTURE_DEVICE}" \
            --file "$transcript_file" \
            --threads 4 \
            --step 5000 \
            --length 10000 \
            --keep 0 \
            --vad-thold 0.8 \
            2>/dev/null
    ) &
    local pid=$!
    echo "$pid" > "$PIDFILE"
    log "Transcription PID: $pid"

    # Wait for it (Ctrl+C will trigger trap)
    trap 'cmd_stop; exit 0' INT TERM
    wait "$pid" 2>/dev/null || true
}

cmd_stop() {
    local stopped=false

    if [[ -f "$PIDFILE" ]]; then
        local pid
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            # Kill the whole process group (rec + whisper pipeline)
            kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
            log "Stopped transcription (PID $pid)"
            stopped=true
        fi
        rm -f "$PIDFILE"
    fi

    stop_sync

    # Also kill any lingering rec/whisper processes from this script
    pkill -f "whisper-cpp-stream.*live" 2>/dev/null || true
    pkill -f "rec.*BlackHole" 2>/dev/null || true

    if ! $stopped; then
        log "No transcription process found"
    fi

    # Final sync
    if [[ -n "${CLOUD_DESKTOP:-}" && -f "${TRANSCRIPT_DIR}/latest.txt" ]]; then
        log "Final sync..."
        scp -q "${TRANSCRIPT_DIR}/latest.txt" "${CLOUD_DESKTOP}:${REMOTE_PATH}" 2>/dev/null || true
    fi
}

cmd_list_devices() {
    local whisper_bin
    if command -v whisper-stream &>/dev/null; then
        whisper_bin="whisper-stream"
    elif [[ -x /opt/homebrew/bin/whisper-stream ]]; then
        whisper_bin="/opt/homebrew/bin/whisper-stream"
    else
        echo "ERROR: whisper-stream not found"
        exit 1
    fi

    log "Listing capture devices..."
    echo ""
    # --capture -1 triggers device listing then fails on model load — capture the device list
    "$whisper_bin" --capture -1 --model /dev/null 2>&1 | grep -E "Capture device #|capture devices:" || true
    echo ""
    echo "Current CAPTURE_DEVICE=${CAPTURE_DEVICE}"
    echo "To change: CAPTURE_DEVICE=<id> $0 start"
}

cmd_status() {
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "Transcription running (PID $(cat "$PIDFILE"))"
        if [[ -f "$SYNC_PIDFILE" ]] && kill -0 "$(cat "$SYNC_PIDFILE")" 2>/dev/null; then
            log "Sync running (PID $(cat "$SYNC_PIDFILE"))"
        fi
        if [[ -L "${TRANSCRIPT_DIR}/latest.txt" ]]; then
            local target
            target=$(readlink "${TRANSCRIPT_DIR}/latest.txt")
            local lines
            lines=$(wc -l < "$target" 2>/dev/null || echo 0)
            log "Transcript: $target ($lines lines)"
        fi
    else
        log "Not running"
    fi
}

# --- Main ---
case "${1:-help}" in
    start)  cmd_start "${2:-}" ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    devices) cmd_list_devices ;;
    *)
        echo "Usage: $0 {start [--sync] | stop | status | devices}"
        echo ""
        echo "  start         Start transcribing from BlackHole"
        echo "  start --sync  Start transcribing + sync to cloud desktop"
        echo "  stop          Stop transcription and sync"
        echo "  status        Check if running"
        echo "  devices       List available capture devices"
        exit 1
        ;;
esac
