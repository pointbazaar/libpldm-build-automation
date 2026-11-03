# Compatibility series

Apply **exactly** in `series` order with `scripts/source.sh`. Each patch was
developed against upstream `main` at
`be4f63e36408921e76d868593176377de84e945e` (libpldm 0.18.0).

1. **Byte order/layout/libc:** Apple OSByteOrder primitives; little-endian
   MinGW identities and builtin big-endian swaps; installed companion header;
   explicit endian includes; bounded Windows substring search. MinGW's
   `-mno-ms-bitfields` is also exported by `libpldm.pc`. GNU packed/cleanup/
   weak attribute checks remain enabled; wire layout is not approximated.
   There are currently no deprecated linker aliases. A new alias deliberately
   fails configuration on Windows/macOS until a portable implementation is
   reviewed; no `--defsym` is silently discarded.
2. **Transport-free tests:** exclude requester instance-ID tests and Linux
   transport tests when `transport=false`; omit the unused weak clock wrapper.
   Always use the supplied pinned GoogleTest source, not a system installation.
   All remaining upstream unit tests, including C++ parser tests, stay enabled.
3. **Offline tool packaging:** install `pd`, use portable diagnostics, and
   preserve binary standard input on Windows.
4. **Darwin UTF-16 type:** Xcode 16.4 has no `<uchar.h>`. An installed
   `libpldm/char16.h` uses Clang's UTF-16 literal type in Darwin C and the
   native C++ keyword; other C targets retain the standard header. No libc
   conversion functions are reimplemented. Native tests check the two-byte
   type, alignment and a surrogate pair; additional C/C++ probes explicitly
   make `<uchar.h>` unavailable to exercise the fallback on every host.

No upstream source is stored here. The full patched source and pinned test
dependency are release assets. Patch application uses `git apply --check`
then `git apply`, with neither three-way fallback nor an already-applied
exception. When upstream incorporates a change, remove/refresh that patch
deliberately, update `series` and this document, and rerun all three native
targets. Never delete a failing patch merely to turn a build green.

Shared libraries are deliberately not shipped. Consequently DLL exports/import
libraries and Mach-O install names/rpaths are not part of this series. A future
shared-library recipe must solve and test those separately.
