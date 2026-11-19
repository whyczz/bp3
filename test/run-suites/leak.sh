#!/usr/bin/env bash
# planted suite: writes into HOME; the runner's HOME must absorb it
set -eu
echo leaked > "$HOME/.bp3-leak"
