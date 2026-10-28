#!/bin/sh
# Stop the OpenOCD process recorded by this run, after verifying its working
# directory. A stale PID file must not terminate another user's process.
set -eu
[ -f ocd.pid ] || exit 0
ocd_run_pid=$(cat ocd.pid)
case "$ocd_run_pid" in ''|*[!0-9]*) exit 1 ;; esac
ocd_run_dir=$(pwd -P)
ocd_process_dir=$(readlink "/proc/$ocd_run_pid/cwd" 2>/dev/null || true)
[ "$ocd_process_dir" = "$ocd_run_dir" ] || exit 0
kill -TERM "$ocd_run_pid" 2>/dev/null || true
