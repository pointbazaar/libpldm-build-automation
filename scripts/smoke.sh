#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"
prefix=$(cd "$1" && pwd)
work=$2
TARGET=$3
mkdir -p "$work"
work=$(cd "$work" && pwd)
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
unset PKG_CONFIG_PATH
stage 'Compile independent installed C and C++ consumers'
meson setup "$work/build" "$ROOT/tests"
meson compile -C "$work/build" -j 3

run_checks() {
    "$work/build/consumer-c"
    "$work/build/consumer-char16"
    "$work/build/consumer-c-header"
    "$work/build/fixture" "$work/fixture.bin"
    "$work/build/consumer-cpp" "$work/fixture.bin"
    "$prefix/bin/pd" < "$work/fixture.bin" > "$work/pd.txt"
    stage "pd firmware fixture output ($TARGET)"
    cat "$work/pd.txt"
    # Ignore platform line endings, blank separators and the image pointer.
    tr -d '\r' < "$work/pd.txt" | sed '/Component image: /d; /^$/d' > "$work/pd.normalized"
    diff -u "$ROOT/tests/pd.expected" "$work/pd.normalized"
    echo 'Installed pd: firmware fixture output matches expected'
    stage 'Check pd rejects empty input (expected failure)'
    if "$prefix/bin/pd" < /dev/null > "$work/pd-empty.txt" 2>&1; then
        fail 'pd incorrectly accepted empty input'
    fi
    grep -Fq 'Failed to parse PLDM package:' "$work/pd-empty.txt"
    echo 'Installed pd: empty input rejected as expected'
}

if [[ $TARGET == windows-x86_64 ]]; then
    # No MSYS2/toolchain DLLs on PATH when any shipped/consumer program runs.
    windows_path=$(cygpath -u "$SYSTEMROOT")
    export PATH="$windows_path/System32:$windows_path:/usr/bin"
fi
stage 'Run consumers and pd with deterministic firmware fixture'
run_checks
