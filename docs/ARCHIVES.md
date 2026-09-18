# Archive implementation and dependencies

Scope: ordinary, unencrypted, single-volume ZIP/CBZ, RAR/CBR, and 7z/CB7. Archive size and image size are separate: each member is limited to 256 MiB; synthetic total archives around 512 MiB and 1 GiB are validated. ZIP currently accepts Stored/Deflate, classic (non-ZIP64) headers, and central directories up to 32 MiB. RAR dictionary requests are capped at 256 MiB. Stream indexes stop at 100,000 entries. Encryption, split volumes, nested archives, and historical formats are outside the current scope.

The Swift `ArchiveStore` shares extracted member bytes across image rendition sizes and pipelines. It checks archive identity before a read, reuses up to two archive sessions, and schedules one member at a time per session. Waiting foreground work is selected ahead of background work between members. Cancellation discards a partially advanced decoder; completed members remain cached. The RAR wrapper serializes native API calls because UnRAR has global error state. No backend writes archive paths to disk: UnRAR uses test/stream callbacks, and libarchive uses read-data calls.

ZIP seeks directly to requested members. Non-solid RAR skips unrelated members. Solid RAR and all 7z sessions cache intervening images when advancing, so reversing direction reuses bytes. The 7z behavior is deliberately conservative: the system library does not expose block membership through its public API. Cache eviction can require replaying an older stream. A shared member cache retains at most 64 MiB in RAM and 1.5 GiB / 4096 members on temporary disk; decoder dictionaries, returned buffers, and rendered pixels are additional memory.

## Reproducible source inputs

`Sources/CUnrar/vendor` contains unmodified `.cpp`/`.hpp` files and upstream notices from:

- https://www.rarlab.com/rar/unrarsrc-7.3.1.tar.gz
- SHA-256: `634900842a3737d9cc15bbcc71d4c74cc713437e0bca296a573424fe5f2660ab`

The compiled source list follows upstream's `makefile` library objects. It defines `RARDLL` and `_FILE_OFFSET_BITS=64`, uses C++17, and does not compile the command-line program. Glint does not depend on a user's installed `rar` or `unrar` executable. `GlintUnrar.cpp` is Glint's new C interface; the vendor sources are unmodified. UnRAR's own license and acknowledgments are bundled in `Resources/ThirdPartyNotices.txt` and retained in the vendor directory.

`Sources/CLibArchive` contains public upstream v3.7.4 headers, linked against the SDK's system `libarchive.2`, without bundling library binaries:

- https://raw.githubusercontent.com/libarchive/libarchive/v3.7.4/libarchive/archive.h — SHA-256 `618cd16c8fa40ddabc44f2d3eb3a35860f6b1d1d856b62a7f4f035b7a319bdab`
- https://raw.githubusercontent.com/libarchive/libarchive/v3.7.4/libarchive/archive_entry.h — SHA-256 `3695eb0193741b16b99e06cf1fc5e6db427b68a9475696ef746c024ae0a6ae72`

Runtime 7z codec compatibility therefore follows the installed macOS library. Common LZMA/LZMA2 solid and independent archives are covered by the tests. There is no claim of compatibility with every 7z codec extension.

When updating either dependency, retain its notices, update the checksums and source list, run `swift test`, build the app, and repeat the archive benchmark matrix in `PERFORMANCE.md`.
