#!/usr/bin/env bash
# tail-transcript.sh — Tail the live meeting transcript on the cloud desktop
#
# Usage:
#   ./tail-transcript.sh              # tail /tmp/live-transcript.txt
#   ./tail-transcript.sh /path/to.txt # tail specific file
#
# For pi integration, start as a background process:
#   process start --name transcript-tail --command "./tail-transcript.sh"

set -euo pipefail

TRANSCRIPT="${1:-/tmp/live-transcript.txt}"
POLL_INTERVAL=2
MARKER_FILE="/tmp/.transcript-read-pos"

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }

# Wait for transcript file to appear
if [[ ! -f "$TRANSCRIPT" ]]; then
    log "Waiting for transcript at $TRANSCRIPT ..."
    while [[ ! -f "$TRANSCRIPT" ]]; do
        sleep "$POLL_INTERVAL"
    done
    log "Transcript file appeared"
fi

log "Tailing: $TRANSCRIPT"
log "Press Ctrl+C to stop"

# Use tail -f for continuous following
# -n +1 starts from beginning; use -n 0 to only show new lines
exec tail -f -n +1 "$TRANSCRIPT"
