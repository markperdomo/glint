# Acknowledgments

Glint is inspired by Xee's quick folder browsing and keyboard-centered image viewing. The supplied Xee source identifies Dag Ågren as the original author and credits later work by CocoaBob, vit9696, and other contributors.

The old application's menu definitions, controller interfaces, source/decoder inventory, preferences, and tests were examined to understand behavior. This repository contains a new Swift implementation and new artwork; it does not bundle Xee's source files, resources, XADMaster, UniversalDetector, Carbon compatibility code, or old decoder libraries.

Apple's frameworks provide the platform image and graphics implementations. ZIP Deflate uses the macOS system zlib. Glint does not vendor a separate copy of zlib.

## Archive libraries

7z reading links to macOS libarchive. Public `archive.h` and `archive_entry.h` headers are pinned to upstream v3.7.4 and retain their BSD notices. RAR reading builds the unmodified official `unrarsrc-7.3.1.tar.gz` sources with `RARDLL`; Glint's wrapper only lists and tests/streams members and never invokes path extraction. UnRAR is distributed under its own license, not Glint's MIT license.

See [ThirdPartyNotices.txt](Resources/ThirdPartyNotices.txt), which is also copied into the built app. Source origins and checksums are in [ARCHIVES.md](docs/ARCHIVES.md).
