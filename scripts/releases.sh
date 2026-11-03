#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Read-only release validation shared by preparation and publication.

release_json() {
    # Listing with pagination distinguishes a missing release from API/auth failure.
    gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
        | jq -s 'add // []'
}

complete_release() {
    local releases=$1 identity=$2 expected=$3
    jq -er --arg identity "$identity" --argjson expected "$expected" '
        [.[] | select(.draft == false and .prerelease == false)
         | select(.body | contains("Build identity: " + $identity + "\n"))
         | select(([.assets[] | select(.state == "uploaded" and .size > 0)
                    | .name] | unique | sort) == ($expected | sort))]
        | first | .tag_name // empty' "$releases"
}

verify_uploaded_assets() {
    local tag=$1 directory=$2
    local verification
    verification=$(mktemp -d)
    gh release download "$tag" --dir "$verification" --repo "$GITHUB_REPOSITORY"
    (cd "$verification" && sha256sum -c SHA256SUMS)
    diff -u <(find "$directory" -maxdepth 1 -type f -printf '%f\n' | sort) \
        <(find "$verification" -maxdepth 1 -type f -printf '%f\n' | sort)
    while IFS= read -r file; do
        cmp "$directory/$file" "$verification/$file"
    done < <(find "$directory" -maxdepth 1 -type f -printf '%f\n')
}
