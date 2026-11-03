#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"
TARGET=keepalive
commit=$1
stage 'Record genuine monthly upstream check'
[[ $commit =~ ^[0-9a-f]{40}$ ]] || fail 'No resolved upstream check to record'
[[ $GITHUB_REF == "refs/heads/$DEFAULT_BRANCH" ]] || fail 'Keepalive only on the default branch'
[[ $GITHUB_EVENT_NAME == schedule || $GITHUB_EVENT_NAME == workflow_dispatch ]] \
    || fail 'Untrusted keepalive event'

git -C "$ROOT" fetch --depth=1 origin "$DEFAULT_BRANCH"
path=.github/sync-status.json
blob=$(git -C "$ROOT" ls-tree FETCH_HEAD -- "$path" | awk '{print $3}')
previous=0
if [[ -n $blob ]]; then
    previous=$(git -C "$ROOT" show "FETCH_HEAD:$path" | jq -er .checked_epoch)
fi
[[ $previous =~ ^[0-9]+$ ]] || fail 'Invalid previous check timestamp'
now=$(date -u +%s)
if (( now - previous < 30 * 24 * 60 * 60 )); then
    echo 'Monthly sync-status update not due.'
    exit 0
fi
status=$(jq -n --arg upstream "$commit" --arg checked "$(date -u +%FT%TZ)" \
    --argjson epoch "$now" \
    '{checked_at: $checked, checked_epoch: $epoch, upstream_main: $upstream,
      meaning: "Upstream check only; not a successful-build indicator"}')
request=$(mktemp)
jq -n --arg branch "$DEFAULT_BRANCH" --arg sha "$blob" \
    --arg content "$(printf '%s\n' "$status" | base64 | tr -d '\n')" \
    '{message: "ci: Record monthly upstream check", branch: $branch,
      content: $content} + if $sha == "" then {} else {sha: $sha} end' > "$request"
gh api --method PUT "repos/$GITHUB_REPOSITORY/contents/$path" --input "$request" > /dev/null
echo '- Monthly upstream check recorded (not a build-success claim).' >> "$GITHUB_STEP_SUMMARY"
