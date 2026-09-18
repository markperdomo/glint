# Performance and validation

## Design constraints

- Directory enumeration, compressed-image decode, and Core Image adjustment rendering run off the main actor.
- The canvas displays an already-decoded image through a persistent Core Animation layer. During uncached navigation, it holds the previous image and framing until the next preview is ready, then swaps pixels and geometry together without a fade. This removes the intervening blank frame; it does not reduce decode time.
- Navigation publishes cached viewer/sidebar pixels synchronously, or decodes a 512-pixel preview before requesting the final 1024/2048/4096/8192-pixel long-edge rendition. A typical window refines to 2048 pixels. High zoom requests 8192 pixels. Metadata and viewport geometry always retain original dimensions.
- The viewer cache retains at most 256 MiB of decoded images; thumbnails retain at most 48 MiB. These are cache limits, **not a total RSS limit**: in-flight decoding, the visible image, image-source internals, Core Image, and compositor textures consume additional memory.
- Prefetch starts symmetrically, then favors the navigation direction after repeated input: ahead 1/2/3, behind 1, ahead 4/5. It warms previews first, then the nearest two renditions, capped at 4096 pixels. Rapid input defers final refinement until 140 ms after the latest navigation input.
- Viewer decoding is bounded to two jobs, with at most one speculative job; thumbnails have an independent single-job pipeline. Identical in-flight requests share a decode. Cancelling a subscriber removes abandoned queued work but lets running work remain adoptable and cacheable. Generation checks prevent stale display updates. These bounds apply to the shared viewer/thumbnail pipelines; export and edit tasks have separate execution paths.

## Reproduce a decode benchmark

```sh
swift Scripts/generate-fixtures.swift /tmp/Glint-Samples
swift run -c release glint-bench /tmp/Glint-Samples 12
```

The fixture script creates twelve 6000 × 4000 JPEG test charts. The benchmark reports directory scan time, cold per-image decode median/p95, reverse-pass duration, cache hits/misses, actual decode/shared-request counts, and retained bytes. It also measures a fresh pipeline doing 512-pixel preview followed by final refinement, and synchronous cache-lookup time. The progressive pass follows the direct pass, so OS and decoder warm-up can differ. Cold means absent from Glint's decoded-image cache; it does not flush the OS filesystem cache.

Use a real collection as well:

```sh
swift run -c release glint-bench /path/to/your/images 100
```

These figures measure scanning and decoding only. They do not measure keyboard-to-display latency or establish that Glint is faster than Xee. Do not claim a speedup without a controlled comparison using identical input files, display scale, rendered resolution, and warm/cold conditions.

### Initial local measurement — September 17, 2026

Apple M4 Max, 36 GB RAM, macOS 27, Xcode 27 / Swift 6.4, optimized build, the twelve generated 24 MP JPEGs:

| Decode limit | Cold median | Cold p95 | Reverse pass | Cache at end |
| --- | --- | --- | --- | --- |
| 4096 px, initial fixed-resolution implementation | 124.87 ms | 153.49 ms | 917.87 ms | 5 hits / 19 misses, 213 MiB |
| 2048 px, window-sized implementation | 42.35 ms | 86.50 ms | 0.244 ms | 12 hits / 12 misses, 127 MiB |

The second run performs less pixel work and keeps the entire sample collection in cache. This is a development sanity check, not a same-resolution speed comparison or a representative photo-library benchmark. Hardware/service warm-up and concurrent development work can affect these single-run numbers. Pass a fourth argument to the benchmark to choose the decode limit, for example `glint-bench /path 12 4096`.

### Progressive-loading sample — September 17, 2026

Same machine and twelve synthetic 24 MP JPEGs, optimized build, 2048-pixel final rendition:

| Operation | Median | p95 |
| --- | --- | --- |
| Direct final decode | 42.24 ms | 82.44 ms |
| Progressive preview available | 6.514 ms | 6.684 ms |
| Progressive final image, including preview work | 49.630 ms | 52.077 ms |
| Synchronous cached-rendition lookup | 0.001 ms | 0.011 ms |

All 12 images had cached renditions at the end. This is one development sample, with no competing prefetch or thumbnail tasks in the benchmark. It demonstrates the earlier-preview/final-refinement tradeoff, not a controlled overall speedup. It excludes input delivery, UI work, compositing, and scanout; cache lookup timing is not input-to-display latency.

## Inspect navigation latency

Use Instruments' Points of Interest and Core Animation tracks with the optimized app. Filter signposts to subsystem `app.glint`, category `Navigation`:

- `Selection to canvas` begins when selection changes and ends when its image is assigned to the canvas layer. Keep only intervals ending with `outcome=submitted`; superseded, failed, and suspended selections are explicitly marked.
- `Preview ready` and `Rendition ready` mark asynchronous decode publication.

Layer submission is **not** a physical presentation timestamp. Correlate these intervals with Core Animation frames to investigate visible hitches; do not report them as keypress-to-photon measurements. Test forward/reverse bursts, abrupt direction changes, cold/cache-hit navigation, zoom during refinement, and large collections while monitoring peak RSS.

## Tests

`swift test` exercises natural sorting, wrapping/clamping, Retina/fit geometry, EXIF orientation, GIF frames/timing, PDFs, corrupt images, archive integrity/bounds/Deflate, export dimensions, original-file preservation, cache invalidation/budgets, stale scan/load cancellation, filtering, selection preservation, folder deletion refresh, immediate zoom/key sequencing, synchronous preview publication and final refinement, directional input prediction, shared-request cancellation and promotion, foreground capacity, abandoned queue removal, and stale in-flight invalidation.

Some tests use the real Image I/O type registry and Core Image renderer. They should run in a normal macOS process; a generic shell sandbox that denies LaunchServices and Metal access can produce unrelated failures.

## Manual release checklist

- Open a single image from Finder, a folder, multiple images, and a CBZ.
- Hold an arrow key in Fit. Confirm the final image, title, and sidebar selection agree.
- Switch to actual pixels and immediately press an arrow. Confirm it pans; Command-arrow still browses.
- Test pinch/double-click zoom and resizing on Retina and external displays.
- Filter filenames, clear the filter, sort/reverse, and open the contact sheet.
- Play/pause an animation and step through a TIFF/PDF.
- Rotate, flip, crop, undo, export, and compare dimensions/pixels with the source. Confirm the original bytes are unchanged.
- Add, overwrite, rename, and remove a disposable image externally while viewing its folder.
- Run a slideshow through both wrap and non-wrap boundaries; Escape must stop it.
- Close/reopen the window and test Finder Open With again.

Before claiming mature parity: benchmark 10,000+ real-image folders, very large panoramas, slow/network volumes, diverse RAW/HDR/color profiles, and pathological animations. Track peak RSS and main-thread work with Instruments' Allocations and Time Profiler.


### Archive benchmark — September 18, 2026

Apple M4 Max, 36 GB RAM, macOS 27.0, Xcode 27.0 / optimized build. Generated independent random 2048 × 1024 PNGs (~6 MiB each), 86 images (~516 MiB) and 171 images (~1026 MiB). These are synthetic images, not a camera RAW or real-photo corpus. Each format has one run; OS file caches were not flushed. Other build activity may affect timings. Pixel caching is disabled in this benchmark, so warm results still include Image I/O decoding.

| Archive | Index ms | First image after index ms | Forward median ms | First jump to last ms | Reverse median ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 512MiB.cbz | 9.025 | 11.351 | 8.441 | 8.530 | 8.790 | 336 |
| 512MiB-independent.rar | 9.289 | 11.323 | 8.654 | 9.671 | 9.355 | 318 |
| 512MiB-solid.rar | 9.921 | 49.623 | 46.792 | 2949.737 | 5.585 | 324 |
| 512MiB-independent.7z | 9.014 | 11.245 | 8.362 | 176.381 | 5.488 | 324 |
| 512MiB-solid.7z | 9.364 | 11.107 | 8.528 | 207.484 | 5.532 | 220 |
| 1GiB.cbz | 11.997 | 11.540 | 8.254 | 8.982 | 8.662 | 336 |
| 1GiB-independent.rar | 11.424 | 11.314 | 8.312 | 7.994 | 7.992 | 319 |
| 1GiB-solid.rar | 13.079 | 47.543 | 44.242 | 7333.610 | 5.424 | 221 |
| 1GiB-independent.7z | 17.083 | 14.147 | 8.553 | 402.493 | 5.260 | 324 |
| 1GiB-solid.7z | 11.227 | 11.256 | 8.402 | 415.371 | 5.322 | 324 |

Solid RAR and 7z performed **zero additional member decompressions** during the reverse pass: intervening image bytes had been cached. ZIP and non-solid RAR skip unrelated members on the initial jump; their reverse pass visits 11 previously unread images. The 1 GiB solid/7z cases retained ~60 MiB of member data in RAM and ~1026 MiB on temporary disk. Peak RSS includes decoder work, frameworks, mapped data, and buffers, and is not a cache-limit claim.

7z currently caches intervening images even for independent blocks because libarchive's public API does not expose block membership. This costs extra work on a first distant jump, while making later backward browsing inexpensive. A solid RAR first jump remains materially slower. These numbers do not establish a speedup over Xee or measure keyboard-to-display latency.

Reproduce (official `rar` and `7zz` tools are needed only to generate fixtures, not to run Glint):

```sh
python3 Scripts/generate-archive-fixtures.py /tmp/Glint-Archives --large --rar /path/to/rar --sevenzip /path/to/7zz
swift run -c release glint-bench --archive /tmp/Glint-Archives/1GiB-solid.rar
```

Sparse 512 MiB / 1 GiB ZIP-offset regressions also run in `swift test`; these test bounded range reads, not representative throughput.
