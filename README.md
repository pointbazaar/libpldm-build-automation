# Unofficial portable libpldm builds

Native Windows/macOS build automation for [openbmc/libpldm](https://github.com/openbmc/libpldm).
This is **not an upstream release or a source fork**. Only automation, small
compatibility patches and tests live here; CI fetches upstream `main` once and
all targets consume the same patched-source archive and automation commit.

**Initial validation status:** the Linux validation build and all 22 applicable
upstream test executables have been exercised locally, along with installed C
and C++ consumers and `pd`. MinGW GCC 16.2 cross-compilation covers both libraries,
`pd`, and the applicable upstream test executables. Native Windows/macOS runs,
GitHub publication and the real keepalive API still require a first Actions run.
Configured targets below are not a claim that those native runs already passed.

## Downloads and targets

[Newest complete downstream build](https://github.com/pointbazaar/libpldm-build-automation/releases/latest)
· [All builds](https://github.com/pointbazaar/libpldm-build-automation/releases)
· [Actions](https://github.com/pointbazaar/libpldm-build-automation/actions/workflows/portable.yml)

The newest link is populated only after a complete successful publication. It
may return 404 before the first release. Fork maintainers must update these links.

| Archive target | Explicit native runner | Toolchain/runtime | Intended minimum OS |
| --- | --- | --- | --- |
| `windows-x86_64` | `windows-2025` | MSYS2 UCRT64 MinGW-w64 GCC (require GCC 14+), UCRT | Windows 10 1809+ x86-64 |
| `macos-arm64` | `macos-15` (arm64) | Xcode 16.4 Apple Clang 17, system libc++ | macOS 15.0 arm64 |
| `macos-x86_64` | `macos-15-intel` | Xcode 16.4 Apple Clang 17, system libc++ | macOS 15.0 Intel |

OS baselines are conservative recipe targets, **not separately tested on the
oldest OS versions**. Native tests run on the resolved runner image. Apple builds
set `MACOSX_DEPLOYMENT_TARGET=15.0`; Windows uses the modern UCRT64 baseline.
The source needs GNU-compatible C17 extensions and C++23 `std::expected`, ranges,
and span. MSVC is not supported. Hosted images and MSYS2 packages change over
time; every archive records actual compiler, dependency, SDK and image versions.
macOS installs Meson 1.9.1; Windows uses the recorded MSYS2 Meson package (upstream
requires >=1.6). The recipe revision can request a refresh after external changes.

### Included components and ABI limitations

* **Static** `libpldm.a` and `libpldm++.a`, public/generated headers and relocatable
  `lib/pkgconfig/libpldm{,++}.pc`. IBM and Meta OEM codecs are enabled.
* Upstream **`pd`**, an offline firmware-package dumper, reading binary stdin:
  `pd < firmware-package.bin`. It has no `--help` option.
* Build identity, target/compiler/dependency metadata, recipe configuration and
  licence notices under `share/libpldm/build/`.

No libpldm DLLs/dylibs or import libraries are shipped. The Windows executable
links compiler runtimes statically (`-static`); it needs Windows/UCRT, not an
MSYS2 installation. CI runs it and external consumers without the UCRT64 DLL
directory on PATH. Compiler/runtime notices are included. Apple binaries use
the system runtime. No signing, notarization, installers or package-manager
integration is provided; macOS quarantine policy may require local approval.

Static libraries do **not** promise cross-compiler or cross-release ABI stability.
Use the same architecture, runtime, compatible compiler and C++ standard library
as the package metadata; especially do not mix MinGW C++ with MSVC or libc++ with
libstdc++. All upstream ABI classes, including testing APIs, are enabled. Rebuild
consumers when updating. Windows consumers must retain `-mno-ms-bitfields` for
PLDM wire layout; `libpldm.pc` supplies it, including through `libpldm++.pc`.

**Excluded deliberately:** `-Dtransport=false` removes Linux AF_MCTP, Unix demux
transport, requester/instance-ID storage APIs and their tests. The installed
upstream headers may still declare these unavailable APIs: do not link against
them. There is no replacement transport. This upstream revision has only one
Meson tool, `pd`; `pldmtool` is not supplied by this source tree. Documentation,
Linux ABI-dump comparisons and fuzz campaigns are not part of binary builds.
The firmware-device state machine, codecs and C++ offline package parser remain
enabled; no other unit tests are disabled to obtain a green result.

### Using an extracted package

Extract the architecture-specific `.tar.gz` (Windows `tar.exe` also supports it).
Install the compatible native compiler and pkg-config for development, then set
`PKG_CONFIG_PATH` to the extracted `lib/pkgconfig` directory. For example:

```sh
cc consumer.c $(pkg-config --cflags --libs --static libpldm) -o consumer
c++ -std=c++23 consumer.cpp $(pkg-config --cflags --libs --static libpldm++) -o consumer-cpp
```

For Windows programs that must run without MinGW DLLs, add `-static` at final
link, as this recipe does. Otherwise distribute the matching compiler runtime
DLLs and their notices yourself. The static archives alone do not bundle every
consumer's runtime. No shared-library search paths or install names are needed.

## Running CI

1. Put the workflow on the repository's **default branch**. For a new repository
   or fork, open **Actions** and enable workflows; approve first-time fork PR
   runs if prompted. Allow the SHA-pinned actions in repository/organization
   Actions policy. No PAT, upstream write access or external scheduler is needed.
2. Open **Portable builds → Run workflow**, select the default branch and run.
   The daily schedule is `17 4 * * *` UTC. GitHub schedules are best effort and
   can be delayed or dropped. Non-default-branch manual runs and pull requests
   build/test only; they cannot publish releases or write sync status.
3. Select **force_rebuild** to bypass the complete-identity skip. The new tag
   includes the workflow run ID and attempt, so it never replaces a successful
   release. On reruns, prefer rerunning **all jobs**, not only failed jobs,
   especially after the 7-day intermediate artifacts expire.

Preparation/build jobs have `contents: read`, no persisted checkout credentials,
and no publishing token. Separate default-branch jobs get `contents: write` for
releases or the one sync-status file. `pull_request`, not `pull_request_target`,
is used for untrusted contributions. One workflow orchestrates every stage; it
does not expect a `GITHUB_TOKEN` push to trigger a second workflow. Trusted runs
are serialized without canceling an active build; all matrix targets can report
failures independently. Keepalive runs after preparation even if builds fail or
the identity is skipped (provided upstream resolution succeeded).

## Identity, publication and recovery

A build identity is the full upstream SHA plus a SHA-256 digest of filenames and
contents in `patches/`, `scripts/`, `config/`, `tests/`, and `.github/workflows/`
(excluding Markdown). This includes the target matrix, dependency pins and action
SHAs. It deliberately excludes README/docs, the sync-status file and automation
commit ID, so a monthly heartbeat does not force a rebuild. The exact automation
commit is still recorded in metadata and is the release tag's target. Changing
unrelated documentation alone can correctly reuse an existing complete identity.

Only a published non-draft, non-prerelease with the matching identity and **all
seven expected, nonempty uploaded assets** skips a build. Failures never record
completion. API/auth errors in release enumeration fail preparation rather than
pretending the identity is complete. A retry or the next daily run tries again.

After all three native jobs succeed, publication validates target identities,
creates `SHA256SUMS`, uploads a **draft**, downloads it again to verify checksums
and exact bytes/asset names, and only then publishes it with `--latest`. These
are ordinary releases for a stable `/releases/latest` link, but their names and
notes explicitly identify **unofficial upstream development builds**. Release
versions are unique, not rolling replacements. Enable GitHub's release
immutability setting for server-enforced protection of published assets/tags.

Each release has three architecture archives, a patched source archive, a recipe
archive (patches/scripts/tests/config/workflow), `build.json` and `SHA256SUMS`.
The source archive includes the pinned GoogleTest source and licence, with `.git`
directories excluded. GitHub's automatic source links contain **this automation
repository**, not patched libpldm; use the explicit `-source.tar.gz` asset.

Failed uploads remain drafts and do not move the successful download pointer.
A subsequent successful attempt reuses an incomplete draft only for the same
identity **and automation revision**, reuploads its assets and verifies it.
`build.json` records the attempt's proposed tag; draft recovery can reuse an older
tag pointing to that same automation revision.
Other drafts are left untouched for diagnosis; remove abandoned drafts manually
if no longer useful. If extra manually added assets make verification fail,
inspect/remove them from the draft before retrying. Never edit a published build
to repair an incomplete set; fix the recipe and publish a new revision.

## Testing and local reproduction

Each target runs all applicable upstream unit tests with assertions enabled,
including C++ parser and UTF-16 msgbuf tests. The Windows bounded substring
fallback is also checked explicitly in C and C++ for empty/truncated/boundary
inputs on every host. Then it archives/extracts the installed package,
hides the original source/build/install paths, builds **external C and C++
consumers using only installed pkg-config metadata**, and tests wire struct
sizes/offsets, exact header bytes, little/big-endian conversions and known CRC32.
`pd` and the C++ parser read a deterministic FR02H fixture containing a Windows
text-mode EOF byte; normalized tool output is compared with `tests/pd.expected`.
Empty input must fail. There are no correctness-critical caches.

For local Linux validation (not a fourth release target), install Bash, Git,
tar, jq, C/C++23 compilers, Meson >=1.6, Ninja, CMake and pkg-config, then use a
**new temporary directory**:

```sh
bash tests/automation.sh
bash scripts/prepare.sh resolve
# Copy the reported exact upstream SHA into the following command:
bash scripts/prepare.sh prepare UPSTREAM_SHA /tmp/opencode/prepared
bash scripts/build.sh linux-local /tmp/opencode/prepared /tmp/opencode/native
```

On native Windows, run `scripts/build.sh windows-x86_64 ...` in MSYS2 UCRT64
with the packages listed in the workflow. On macOS select Xcode 16.4 and use the
matching `macos-arm64` / `macos-x86_64` target. The prepared source is verified
against `preparation.sha256` and the current recipe digest before building.
For exact archived reproduction, extract the recipe asset and source asset,
use the recorded dependency/toolchain versions and native build options in
`share/libpldm/build/`; hosted images and package mirrors are not frozen snapshots,
so bit-for-bit binaries are not guaranteed. Keep the automation checkout at the
recorded revision when reproducing CI inputs.

Offline automation tests mock GitHub (no publication/status writes) and cover
complete-only skips, invalid assets, recipe digest scope, forced revisions,
draft recovery, upload failure, incomplete targets and monthly status updates.
Use `shellcheck -x scripts/*.sh tests/*.sh` and `actionlint` for static checks.
Format changed Meson files with `meson format -i` and C/C++ with `clang-format`.

## Maintenance and inactivity

* Refresh patches deliberately using [patches/README.md](patches/README.md).
  A fetch/patch/build/test/package failure blocks publication and appears in the
  Actions summary. Start with the failed step and the 7-day `diagnostics-*`
  artifacts (`meson-logs`, introspection and consumer output). A patch conflict
  is never skipped, even when a patch looks already upstream.
* Actions are pinned to full commit SHAs. When updating, inspect upstream release
  notes, action source and inputs/permissions, resolve the tag with `git ls-remote`,
  update all occurrences, and run offline tests and all native targets. Current
  pins are checkout v4, upload/download-artifact v4 and setup-msys2 v2. Dependency
  pins live in `config/recipe.env`; GoogleTest is commit-pinned rather than HEAD.
  Bump `RECIPE_REVISION` after deliberate external compiler/image refreshes.
* About every 30 days, after resolving upstream, the isolated keepalive job uses
  the Contents API to commit **only** `.github/sync-status.json` to the default
  branch. It records check time/epoch and upstream SHA, **not build success**.
  Concurrent edits fail safely. It requires `contents: write` and branch rules
  permitting this bot's file update; required PRs/signatures/rulesets may block
  it. Arrange a narrowly scoped permitted bot path/process, or maintain genuine
  repository activity manually. No blanket protection bypass or PAT is assumed.
* GitHub can disable public scheduled workflows after **60 inactive days**.
  Commit-based keepalive is a workaround, not an uptime guarantee. Monitor its
  failures. Re-enable in Actions → Portable builds → Enable workflow, or use
  `gh workflow enable portable.yml`, then manually dispatch a default-branch run.
  A disabled workflow cannot keep itself alive; if upstream cannot be resolved,
  no check is fabricated and no keepalive is written.
* Standard public hosted runners have free execution, **not unlimited storage**.
  Prepared inputs, packages and diagnostics expire after 7 days; durable downloads
  are Release assets. GitHub currently lists 500 MB included Actions artifact
  storage on Free (other plans differ), so monitor actual usage and prune old
  run artifacts if necessary. Caches are not used. Release storage is separate;
  keep individual assets below GitHub's 2 GiB per-asset limit. Signing and long-term
  retention policy are separate future work.

## References

GitHub runner labels, inactivity, token behaviour and CLI publication semantics
were checked against current documentation during implementation:

* [Workflow triggers, schedules and forks](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
* [Hosted runner labels and architectures](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
* [macOS 15 image / Xcode versions](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
* [GITHUB_TOKEN event limitations](https://docs.github.com/en/actions/concepts/security/github_token)
* [Enable/disable workflows and 60-day inactivity](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows)
* [Release distribution](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
* [gh release create / immutable releases](https://cli.github.com/manual/gh_release_create)
* [Actions limits and storage](https://docs.github.com/en/actions/reference/limits)
* [Download Actions artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)
