#!/usr/bin/env bash
# planted suite: never finishes; records its child's pid so the
# test can prove the whole process group died at the budget
set -eu
sleep 999 &
echo $! > "$1"
wait
