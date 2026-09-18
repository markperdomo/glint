# Performance and validation

## Design constraints

- Directory enumeration, compressed-image decode, and Core Image adjustment rendering run off the main actor.
- The canvas displays an already-decoded image through a persistent Core Animation layer.
- Normal browsing chooses a 1024/2048/4096/8192-pixel long-edge rendition based on the window. A typical window starts at 2048 pixels. High zoom requests 8192 pixels. Metadata retains original dimensions.
- The viewer cache retains at most 256 MiB of decoded images; thumbnails retain at most 48 MiB. These are cache limits, **not a total RSS limit**: in-flight decoding, the visible image, image-source internals, Core Image, and compositor textures consume additional memory.
- Prefetch visits next, previous, next+2, previous−2, one at a time. Cancellation and generation checks keep obsolete results off screen.
- Thumbnail work has a separate serial worker so a contact sheet does not queue work in front of the current image. Cache lookup remains available while its worker is decoding another image.

## Reproduce a decode benchmark

```sh
swift Scripts/generate-fixtures.swift /tmp/Glint-Samples
swift run -c release glint-bench /tmp/Glint-Samples 12
```

The fixture script creates twelve 6000 × 4000 JPEG test charts. The benchmark reports directory scan time, cold per-image decode median/p95, reverse-pass duration, cache hits/misses, and retained bytes. Cold means absent from Glint's decoded-image cache; it does not flush the OS filesystem cache.

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

## Tests

`swift test` exercises natural sorting, wrapping/clamping, Retina/fit geometry, EXIF orientation, GIF frames/timing, PDFs, corrupt images, archive integrity/bounds/Deflate, export dimensions, original-file preservation, cache invalidation/budgets, stale scan/load cancellation, filtering, selection preservation, folder deletion refresh, and immediate zoom/key sequencing.

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
