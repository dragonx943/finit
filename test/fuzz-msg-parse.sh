#!/bin/sh
# libink: __msg_parse() against truncation, corruption, and garbage.
#
# Runs the fuzz target's fixed sweep, which is the same contract check
# libFuzzer drives, so the suite covers it on every build without
# needing clang.  Anything it finds aborts, and the sanitizers CI
# builds with turn a stray read into a failure here rather than a
# puzzle on a target.

set -eu

TEST_DIR=$(dirname "$0")
DRIVER="$TEST_DIR/src/fuzz-msg-parse"

[ -x "$DRIVER" ] || {
    echo "fuzz-msg-parse not built, D-Bus support is off"
    exit 77
}

exec "$DRIVER"
