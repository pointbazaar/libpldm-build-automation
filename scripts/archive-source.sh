#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"

source_tree=$(cd "$1" && pwd -P)
archive=$2
stage 'Archive patched source with portable regular-file entries'

# MSYS2's default symlink emulation copies the link target. That fails if the
# target appears later in the tar stream, as scripts/run-ci -> pre-submit does.
# Validate before dereferencing: never copy files outside the fetched source,
# Git metadata, directory links (which may recurse), or broken link targets.
find "$source_tree" -name .git -prune -o -type l -print0 \
    | while IFS= read -r -d '' link; do
        target=$(realpath -e -- "$link") || fail "Cannot resolve source symlink: $link"
        [[ $target == "$source_tree/"* && -f $target ]] \
            || fail "Source symlink must resolve to an internal regular file: $link"
        case ${target#"$source_tree/"} in
            .git|.git/*|*/.git|*/.git/*) fail "Source symlink points to Git metadata: $link" ;;
        esac
    done

tar --dereference --hard-dereference --exclude=.git -czf "$archive" \
    -C "$(dirname "$source_tree")" "$(basename "$source_tree")"
