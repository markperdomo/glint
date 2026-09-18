# Xee reimplementation inventory

Inventory based on the supplied Xee project's controllers, image/source classes, preferences, menu definitions, and tests. “Implemented” describes the current code, not a claim of exhaustive format compatibility or equivalent performance.

| Xee capability | Glint 0.1 | Notes / next work |
| --- | --- | --- |
| Open an image and browse siblings | Implemented | No import database |
| Seamless image switching | Implemented | Holds the current image and framing until the next preview is ready; no intervening blank frame or fade |
| Open folders and multiple files | Implemented | Hidden files and packages skipped |
| Recursive browsing | Implemented | Explicit opt-in; symlink subtrees skipped |
| Next/previous/first/last | Implemented | Arrow keys, Space, Home/End, menu commands |
| Jumps of 10/100 images | Implemented | Shift/Option arrows |
| Natural filename, size, date sorting | Implemented | Adds file-type sort and reverse order |
| Loop browsing | Implemented | Persistent preference |
| Random image and previous random | Implemented | Bounded navigation history |
| Slideshow and random slideshow | Implemented | Configurable 0.5–30-second interval; prevents display sleep |
| Live file/directory changes | Partial | Root directory and current file; full recursive subtree watching remains |
| Fit / shrink / enlarge / actual / fill | Implemented | Retina-aware geometry and overflow tolerance |
| Preserve zoom | Implemented | Settings preference |
| Preserve pan/focus across images | Planned | New images currently recenter |
| Pan, wheel, interpolation | Implemented | Off / mouse wheel / mouse wheel and trackpad scroll navigation; one image per trackpad gesture, momentum ignored; pinch zoom and sharp-pixel mode |
| Full screen and hide chrome | Implemented | Native full screen and distraction-free mode |
| Automatic window sizing/placement rules | Planned | Native resizable window today |
| Multiple independent viewer windows | Planned | One browsing session today |
| Thumbnail browsing | Implemented | Sidebar and contact sheet |
| EXIF orientation | Implemented | Applied during Image I/O decode |
| Toggle raw vs EXIF orientation | Planned | Auto-orientation currently always enabled |
| Metadata and properties | Implemented | Image I/O properties, profiles, EXIF/IPTC/GPS when supplied |
| Embedded thumbnail editing | Planned | Not needed for the initial browsing workflow |
| GIF/APNG/WebP playback | Partial | Decoded through Image I/O; loops continuously; finite-loop semantics and frame scheduling need refinement |
| Multi-frame TIFF / icons | Implemented | Frame stepping for Image I/O image collections |
| PDF sources | Implemented | Page stepping and raster export; password entry remains |
| ZIP/CBZ archives | Implemented, constrained | Indexed range reads, Stored/Deflate, CRC validation, 256 MiB per-member limit; total archives tested around 512 MiB and 1 GiB |
| RAR/CBR and 7z/CB7 | Implemented | UnRAR handles RAR4/RAR5 including solid streams; system libarchive handles 7z. Shared 64 MiB RAM / 1.5 GiB disk member cache; no external tools required |
| Encrypted archives, split volumes, ZIP64 | Out of current scope | Focus is ordinary unencrypted ZIP/RAR/7z and browsing speed |
| Nested archives and archive password UI | Out of current scope | Nested archive members are skipped; encrypted sources report an error |
| Clipboard source and image copy | Implemented | Clipboard images get temporary TIFF files; copied output is display resolution |
| Rotate, mirror, crop | Implemented | Temporary previews and full-resolution export |
| Undo/redo adjustments | Implemented | Separate adjustment history; no filesystem undo |
| Lossless JPEG rotation/crop/save | Planned | Requires a modern coefficient-domain JPEG implementation; current exports re-encode |
| Format export | Implemented | PNG, JPEG, HEIC, TIFF; source metadata omitted |
| Rename, Trash, copy/move | Implemented | No silent collision overwrite; Trash confirmation |
| Numbered saved copy/move destinations | Planned | Destination picker available today |
| Reveal / external editor | Partial | Finder and Preview implemented; choose-default-editor preference remains |
| Print | Implemented | Uses current display rendition; full-resolution print pipeline remains |
| Camera RAW and PSD composite | OS dependent | Uses Image I/O support on the installed OS; no dedicated RAW controls or PSD layer browser |
| PNM/PBM/PGM/PPM, XBM | OS dependent | Only variants provided by Image I/O; no independent compatibility guarantee |
| Custom PCX, XPM, ILBM/IFF, Maya IFF, Dreamcast PVR | Planned | Dedicated decoder modules and redistributable conformance fixtures needed |
| Photoshop layers, old PICT variants, SWF image extraction | Planned / evaluate | Isolate archival compatibility from the common-format path |
| Localization, remappable shortcuts | Planned | English and a documented default key map today |
| HDR / wide color | Partial | Preserves decoded profiles and uses modern layer dynamic-range preference; edits/export are 8-bit SDR, gain-map/HDR fidelity needs validation |

## Next milestones

1. **Make everyday browsing dependable:** real-photo benchmarks against Xee, very large folders, file operation recovery, pan persistence, shortcut customization, and full-resolution tiling beyond the 8192-pixel viewing limit.
2. **Finish modern source coverage:** archive performance across real collections, finite animation loops and frame timing, recursive file watching, independent windows, and security-scoped bookmarks.
3. **Recover specialist workflows:** coefficient-domain JPEG transforms, metadata-preserving export, saved destinations, user-selectable editors, RAW/HDR fidelity, and full-resolution printing.
4. **Historical format compatibility:** audited modern decoder modules, malformed-input tests, and a representative corpus for each old format. Keep these modules away from the common browsing path.
5. **Distribution:** signing, notarization, accessibility audit, localization, crash reporting opt-in if desired, and release automation.
