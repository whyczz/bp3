#!/usr/bin/env bash
# planted suite: records the environment it was given
set -eu
env | sort > "$1"
