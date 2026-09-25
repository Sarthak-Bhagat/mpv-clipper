#!/usr/bin/env bash
# Live check: drive a real, headless mpv through B → seek → B on a real file and
# report what clipper.lua logged. Loads THIS repo's clipper.lua, not the
# installed copy, and writes clips to a temp dir, not the configured outdir.
#
#   ./test.sh FILE [START] [END]      (seconds; defaults 600.5 and 603.0)
#
# Use an old library file. Recent downloads get watched and deleted within days.
#
# Isolation, each flag for a reason:
#   --load-scripts=no          skips ~/.config/mpv/scripts. The installed copy
#                              would bind B twice, and discord.lua re-sets
#                              input-ipc-server to /tmp/mpvsocket at runtime,
#                              which unlinks the live player's socket.
#   --input-ipc-server         a private socket, for the same reason.
#   --save-position-on-quit=no otherwise mpv.conf writes a resume point for FILE
#                              into ~/.local/state/mpv/watch_later.
#   --log-file                 mpv.conf sends nothing to the terminal.
set -u

file=${1:?usage: ./test.sh FILE [START] [END]}
start=${2:-600.5}
end=${3:-603.0}
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d /tmp/mpv-clipper-test.XXXXXX)
sock=$tmp/mpv.sock
log=$tmp/mpv.log

ipc() { printf '%s\n' "$1" | socat - "$sock" >/dev/null; }

mpv --load-scripts=no --script="$here/clipper.lua" \
    --script-opts-append=clipper-outdir="$tmp/out" \
    --input-ipc-server="$sock" --save-position-on-quit=no --log-file="$log" \
    --vo=null --ao=null --pause=yes --sid=1 --start="$start" \
    "$file" >/dev/null 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null' EXIT

for _ in $(seq 100); do [ -S "$sock" ] && break; sleep 0.1; done
sleep 1
ipc '{"command":["keypress","B"]}'
ipc "{\"command\":[\"seek\",\"$end\",\"absolute\"]}"
sleep 0.5
ipc '{"command":["keypress","B"]}'

for _ in $(seq 240); do grep -qE 'clipper\].*(saved|failed)' "$log" && break; sleep 0.5; done
grep -E '\]\[(i|w|e)\]\[clipper\]' "$log" | sed 's/^\[[^]]*\]//'
echo "output: $tmp/out"
ls -l "$tmp/out" 2>/dev/null

grep -q 'clipper\].*saved' "$log"
