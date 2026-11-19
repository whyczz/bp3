#!/usr/bin/env bash
# planted suite: holds an exclusive lock dir for 1s; a second
# holder at the same time fails, so overlap is observable
set -eu
mkdir "$1" 2>/dev/null || { echo "lock held: overlap" >&2; exit 1; }
sleep 1
rmdir "$1"
