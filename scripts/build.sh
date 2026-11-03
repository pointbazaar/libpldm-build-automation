#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"

TARGET=$1
input=$(cd "$2" && pwd)
work=$3
mkdir -p "$work"
work=$(cd "$work" && pwd)
identity=$(jq -r .identity "$input/build.json")
package="libpldm-$identity-$TARGET"
prefix="$work/$package"

configure_target() {
    case "$TARGET" in
        windows-x86_64)
            [[ ${MSYSTEM:-} == UCRT64 && $(uname -m) == x86_64 ]] || fail 'Use native MSYS2 UCRT64 x86-64'
            export CC=gcc CXX=g++
            (( $(gcc -dumpversion | cut -d. -f1) >= 14 )) || fail 'GCC 14+ is required'
            export LDFLAGS=-static
            BASELINE='Windows 10 1809+ x86-64; UCRT; MinGW-w64; no MSVC ABI'
            ;;
        macos-arm64|macos-x86_64)
            [[ $(uname -s) == Darwin ]] || fail 'Use a native macOS host'
            local expected=${TARGET#macos-}
            [[ $(uname -m) == "$expected" ]] || fail "Wrong architecture: expected $expected"
            export CC=clang CXX=clang++ MACOSX_DEPLOYMENT_TARGET
            BASELINE="macOS $MACOSX_DEPLOYMENT_TARGET+; Apple Clang/libc++; $expected"
            ;;
        linux-local)
            BASELINE='Local Linux validation only; not a release target'
            ;;
        *) fail "Unknown target: $TARGET" ;;
    esac
}

build_and_install() {
    local digest expected_digest
    stage 'Verify and extract prepared source'
    (cd "$input" && sha256 -c preparation.sha256)
    digest=$(bash "$ROOT/scripts/identity.sh")
    expected_digest=$(jq -r .digest "$input/build.json")
    [[ $digest == "$expected_digest" ]] \
        || fail "Recipe digest mismatch: expected $expected_digest, got $digest"
    tar -xzf "$input/libpldm-$identity-source.tar.gz" -C "$work"
    cmp "$work/libpldm/UPSTREAM-COMMIT" <(jq -r .upstream "$input/build.json")
    stage 'Configure native Meson build'
    meson setup "$work/build" "$work/libpldm" --prefix="$prefix" --libdir=lib \
        --buildtype=release --default-library=static -Db_ndebug=false \
        -Dtransport=false -Dbindings=cpp -Dtools=pd -Doem=ibm,meta \
        -Dabi=deprecated,stable,testing -Dtests=true -Dtest-methods=unit \
        -Ddocumentation=disabled -Dabi-compliance-check=false --wrap-mode=nofallback
    stage 'Build libraries, tools and applicable upstream tests'
    meson compile -C "$work/build" -j 3
    stage 'Run applicable upstream tests'
    meson test -C "$work/build" --print-errorlogs --no-rebuild
    test_portability_helpers
    stage 'Install package'
    meson install -C "$work/build" --no-rebuild --skip-subprojects
}

test_portability_helpers() {
    local flags=(-O2)
    if [[ $TARGET == windows-x86_64 ]]; then flags+=(-static); fi
    stage 'Check Windows substring fallback boundaries in C and C++'
    "${CC:-cc}" -std=c17 -Wall -Wextra -Werror "${flags[@]}" -I"$work/libpldm/src" \
        "$ROOT/tests/fallback.c" -o "$work/fallback-c"
    "${CXX:-c++}" -std=c++23 -Wall -Wextra -Werror "${flags[@]}" -I"$work/libpldm/src" \
        -x c++ "$ROOT/tests/fallback.c" -o "$work/fallback-cpp"
    "$work/fallback-c"
    "$work/fallback-cpp"
    stage 'Check Darwin UTF-16 types in C and C++ without uchar.h'
    "${CC:-cc}" -std=c17 -Wall -Wextra -Werror "${flags[@]}" -D__APPLE__ \
        -I"$ROOT/tests/no-uchar" -I"$work/libpldm/include" \
        "$ROOT/tests/char16.c" -o "$work/char16-c"
    "${CXX:-c++}" -std=c++23 -Wall -Wextra -Werror "${flags[@]}" -D__APPLE__ \
        -I"$ROOT/tests/no-uchar" -I"$work/libpldm/include" \
        -x c++ "$ROOT/tests/char16.c" -o "$work/char16-cpp"
    "$work/char16-c"
    "$work/char16-cpp"
}

record_metadata() {
    local metadata="$prefix/share/libpldm/build"
    mkdir -p "$metadata/licenses"
    cp "$input/build.json" "$metadata/identity.json"
    cp "$work/libpldm/LICENSE" "$metadata/licenses/libpldm-LICENSE"
    cp "$work/libpldm/subprojects/googletest/LICENSE" "$metadata/licenses/googletest-LICENSE"
    cp "$ROOT/LICENSE" "$metadata/licenses/automation-LICENSE"
    cp "$ROOT/config/recipe.env" "$metadata/"
    cp "$ROOT/README.md" "$metadata/PACKAGE-README.md"
    meson introspect "$work/build" --buildoptions > "$metadata/meson-options.json"
    meson introspect "$work/build" --compilers > "$metadata/compilers.json"
    meson introspect "$work/build" --dependencies > "$metadata/dependencies.json"
    jq -n --arg target "$TARGET" --arg baseline "$BASELINE" \
        --arg cc "$("${CC:-cc}" --version)" --arg cpp "$("${CXX:-c++}" --version)" \
        --arg os "$(uname -a)" --arg image "${ImageOS:-local}/${ImageVersion:-unknown}" \
        --arg gtest "$GOOGLETEST_COMMIT" --arg meson "$(meson --version)" \
        --arg ninja "$(ninja --version)" --arg pkgconf "$(pkg-config --version)" \
        --arg cmake "$(cmake --version)" \
        '{target: $target, baseline: $baseline, c_compiler: $cc, cpp_compiler: $cpp,
          os: $os, runner_image: $image, googletest: $gtest, meson: $meson,
          ninja: $ninja, pkgconf: $pkgconf, cmake: $cmake,
          libraries: "static", assertions: true}' \
        > "$metadata/target.json"
    if command -v pacman >/dev/null; then pacman -Q > "$metadata/packages.txt"; fi
    if [[ $TARGET == windows-x86_64 ]]; then
        pacman -Ql | awk '$2 ~ /\/share\/licenses\// && $2 !~ /\/$/ {print $2}' \
            > "$work/license-files.txt"
        while IFS= read -r notice; do
            [[ ! -f $notice ]] || cp --parents "$notice" "$metadata/licenses/"
        done < "$work/license-files.txt"
    fi
    if [[ $(uname -s) == Darwin ]]; then
        sw_vers > "$metadata/macos.txt"
        xcodebuild -version >> "$metadata/macos.txt"
        xcrun --show-sdk-version >> "$metadata/macos.txt"
        brew list --versions > "$metadata/packages.txt"
    fi
}

relocate_pkgconfig() {
    local pc
    # Meson emits an absolute prefix. Make both installed .pc files relocatable.
    for pc in "$prefix"/lib/pkgconfig/*.pc; do
        # Keep pkg-config's variable reference literal, not a shell expansion.
        # shellcheck disable=SC2016
        sed 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$pc" > "$pc.new"
        mv "$pc.new" "$pc"
    done
}

package_and_test() {
    stage 'Record metadata and package'
    record_metadata
    relocate_pkgconfig
    mkdir -p "$work/dist" "$work/relocated"
    tar -czf "$work/dist/$package.tar.gz" -C "$work" "$package"
    tar -xzf "$work/dist/$package.tar.gz" -C "$work/relocated"
    # Hide original source, build, install and prepared archives during checks.
    mv "$work/build" "$work/build.unavailable"
    mv "$work/libpldm" "$work/source.unavailable"
    mv "$prefix" "$prefix.unavailable"
    stage 'Test extracted package outside original source/build/install paths'
    bash "$ROOT/scripts/smoke.sh" "$work/relocated/$package" "$work/consumer" "$TARGET"
    stage 'Package ready'
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        echo "- **$TARGET**: upstream tests and relocated C/C++/pd checks succeeded." >> "$GITHUB_STEP_SUMMARY"
    fi
}

configure_target
build_and_install
package_and_test
