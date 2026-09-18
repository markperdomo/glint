# Working on Glint

Glint is a native, keyboard-first macOS image viewer inspired by Xee. Fast, dependable folder and archive browsing is the priority. Prefer focused changes that preserve responsiveness and native macOS behavior over adding dependencies or recreating every historical Xee feature.

## Start here

- Inspect `git status` and the relevant diff before editing. The worktree may contain unfinished user or agent work; preserve changes outside your task.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/FEATURES.md](docs/FEATURES.md) for development expectations and implemented versus planned behavior.
- Consult [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for concurrency and presentation, [docs/ARCHIVES.md](docs/ARCHIVES.md) for archive internals, and [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for measurement methods.
- Keep changes within the requested scope. Do not turn a browsing fix into a decoder, rendering, or UI rewrite.

## Platform and code map

Requires Apple silicon, macOS 26+, and Xcode 26+ with Swift 6.2+. Use Swift 6 concurrency checking. The app uses SwiftUI, AppKit, Image I/O, Core Animation, and Core Image; it has no remote Swift package dependencies.

| Location | Responsibility |
| --- | --- |
| `Sources/Glint/ViewerModel.swift` | Main-actor observable browsing session, selection, load generations, progressive loading, edits, playback |
| `Sources/Glint/CanvasView.swift` | AppKit canvas, persistent image layer, image presentation, zoom/pan, keyboard and pointer routing |
| `Sources/Glint/ScrollNavigation.swift` | Wheel/trackpad gesture classification and navigation boundaries |
| `Sources/Glint/` | SwiftUI windows, sidebar, contact sheet, inspector, preferences, commands, file actions |
| `Sources/GlintCore/ImagePipeline.swift` | Bounded decode scheduling, shared requests, rendition caches, foreground priority |
| `Sources/GlintCore/ImageDecoder.swift` | Image I/O and PDF decoding, original dimensions, immutable decode results |
| `Sources/GlintCore/` | Asset identity, folder scanning, browsing prediction, viewport geometry, image editing/export, archive readers and caching |
| `Sources/CZlib`, `Sources/CLibArchive`, `Sources/CUnrar` | Native archive dependencies and the UnRAR C interface |
| `Sources/GlintBench/` | Decode and archive benchmarks |
| `Tests/GlintCoreTests/`, `Tests/GlintTests/` | Swift Testing core, model, canvas, and input regressions |
| `Scripts/generate-project.py` | Source of truth for the checked-in Xcode project |

## Behavior to preserve

- Keep enumeration, file reads, decompression, image decoding, and adjustment rendering off the main actor. Synchronous cache lookup on the main actor must remain memory-only.
- Keep decode concurrency and caches bounded. Foreground navigation must retain capacity ahead of speculative prefetch. Preserve request coalescing, cancellation, and stale-result rejection; old scans or decodes must never replace a newer selection.
- Navigation should publish a cached rendition immediately when available, otherwise request a small preview before full refinement. Keep original image dimensions separate from rendition dimensions so metadata, aspect ratio, and zoom remain correct.
- **Do not reintroduce black flashes between images.** During an uncached load, the canvas retains its previous pixels, zoom, and pan until the next preview is ready. Replace pixels and geometry together without a fade. This retained presentation belongs only to the canvas: model pixels and metadata must describe the current selection, so copy/edit actions cannot use the previous image as the new one. Clear the canvas on a failed load or empty selection.
- Preserve stable asset IDs and constant-time ordinary navigation. Sorting, filtering, refresh, and deletion must preserve selection when possible and choose a valid survivor otherwise.
- At 100%, one source pixel maps to one display pixel, including Retina. Fit preserves aspect ratio and enlarges small images by default, subject to the saved preference. Ordinary arrows pan on an overflowing axis; Command-arrow always browses. Input must respect a zoom change immediately, even before SwiftUI refreshes the canvas.
- Respect text fields, attached sheets, and window focus when handling keys. Preserve scroll-navigation preferences, one advance per trackpad gesture, and suppression of momentum-driven skipping.
- Browsing does not modify originals. Adjustments are temporary; export reads the source independently and refuses to overwrite the original path. Preserve file-operation collision checks and existing Trash confirmation.
- Keep the app local: no analytics, network services, or automatic uploads are part of the product.

## Archive scope and performance

The agreed scope is ordinary, unencrypted, single-volume ZIP/CBZ, RAR/CBR, and 7z/CB7. Fast browsing of archives around 512 MiB–1 GiB matters more than expanding format coverage. Encryption, split volumes, nested archives, and ZIP64 remain outside scope unless explicitly requested.

- The **256 MiB per-member limit is separate from total archive size**. Do not reject a large archive merely because its total size exceeds that limit.
- ZIP uses indexed range reads and Stored/Deflate with integrity checks; RAR uses vendored UnRAR; 7z uses the system libarchive. The app must not require an installed archive CLI or eagerly unpack an entire archive just to open it.
- Solid archives may need to decode preceding data. Preserve shared extracted-member caching across rendition sizes and pipelines so revisiting images avoids unnecessary decompression. Keep memory/disk budgets, identity checks, cancellation, and cache cleanup intact.
- Never extract archive-controlled paths to the filesystem. Temporary cache entries use generated names. Treat filenames, sizes, offsets, and compressed streams as untrusted input.
- Keep upstream vendor sources and license notices intact. Dependency updates must also update the documented provenance/checksums, source lists, bundled notices, and archive validation described in `docs/ARCHIVES.md`.

## Build, test, and verify

For code changes, follow the repository checks:

```sh
swift test
swift format lint --strict --recursive Sources Tests Package.swift
python3 Scripts/generate-project.py
./Scripts/build.sh
git diff --check
```

Use `swift format format --in-place` on edited Swift files when needed. Regenerate the Xcode project after adding/removing app sources or changing project configuration; edit the generator rather than only `project.pbxproj`. Keep the generated project in sync: CI checks for drift.

The Release app is `build/Build/Products/Release/Glint.app`. Use this bundle to check actual UI behavior and Finder integration; `swift run Glint /path/to/images` is only a quick development launch. Local builds use ad hoc signing and are not notarized distribution builds.

- Add focused regressions for changes to archive parsing, geometry, caches, selection, export, or interaction behavior. Prefer observable behavior over tests that mirror implementation.
- Use generated or redistributable fixtures. Keep large benchmarks under a temporary directory, and never commit private photos, archives, credentials, build output, or signing identities.
- Tests use real macOS frameworks. A restrictive runner that blocks LaunchServices or Metal can cause environmental failures; identify those rather than weakening the tests or changing image behavior to hide them.
- Exercise the changed interaction in the built app. For navigation changes, include rapid forward/reverse input, uncached and cached loads, zoom then arrow input, differing aspect ratios, and failure/empty states as relevant.
- Documentation-only changes need link/path and whitespace checks; do not rebuild the app solely for prose edits.
- Report what changed, checks actually run, material limitations, and macOS/Xcode versions for app validation. Do not present unrun checks as passing.

For performance changes, generate samples and run the optimized benchmark:

```sh
swift Scripts/generate-fixtures.swift /tmp/Glint-Samples
swift run -c release glint-bench /tmp/Glint-Samples 12
```

Follow `docs/PERFORMANCE.md` for archive benchmarks and Instruments signposts. Compare identical inputs, resolution, and cache conditions. Decode time, preview readiness, layer submission, and physical display latency are distinct measurements; smoother presentation alone is not a measured decode speedup. Cache budgets are not total process memory limits.

Update the README and relevant feature, architecture, performance, or validation documents when behavior changes. Keep limitations explicit and avoid copying transient test counts or benchmark results into this file.
