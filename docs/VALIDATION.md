# Initial validation

Validated locally on September 17, 2026 using an Apple M4 Max Mac Studio, macOS 27.0, Xcode 27.0, and Swift 6.4.

- Swift package: **21 tests pass** across the core and viewer-model suites, including parameterized stored/Deflate ZIP cases.
- Native Xcode app: Debug and optimized Release builds succeed for arm64.
- Release bundle: ad hoc code-signature verification succeeds.
- Swift source: `swift format lint --strict --recursive Sources Tests Package.swift` passes.
- App plist and generated Xcode project pass `plutil -lint`.
- Actual app launch verified: welcome screen, native toolbar, opening a folder, thumbnail display, matching image/title/selection during repeated arrow navigation, and sidebar hiding.
- The immediate zoom-then-arrow edge case found during UI testing has a regression test.
- Generated 24-megapixel JPEG collection measured with the release benchmark; see [the recorded results](PERFORMANCE.md).

The GitHub workflow has been prepared but has not run on GitHub. No remote repository was created or pushed. The older Xee project was read for behavior and feature discovery and was not modified.

Full legacy feature parity, broad real-world codec compatibility, HDR fidelity, signed/notarized distribution, and a complete accessibility audit remain future work. See [the feature inventory](FEATURES.md).

## Progressive browsing validation — September 17, 2026

Validated on the same macOS 27.0 / Xcode 27.0 machine:

- **34 tests pass**: 25 core tests and 9 viewer-model tests, including shared in-flight decoding, queued promotion/cancellation, reserved foreground capacity, stale-result invalidation, synchronous cached previews, large-image refinement, and direction changes.
- Optimized Xcode app builds successfully; ad hoc signature, plist/project validation, strict Swift formatting, and diff whitespace checks pass.
- Restarted the app with the updated executable and exercised ten forward/four reverse arrow presses, immediate actual-size zoom then pan, Command-arrow navigation, Fit, contact sheet, and contact-sheet selection. Canvas pixels, title, and sidebar selection agreed.
- Measured preview availability and refinement separately on the generated 24 MP JPEGs; see [performance results and measurement limits](PERFORMANCE.md#progressive-loading-sample--september-17-2026).
- Added Instruments signposts for selection-to-layer-submission and asynchronous preview/final-image readiness. Physical input-to-display latency has not been measured.

## Scroll navigation validation — September 18, 2026

Validated on macOS 27.0 / Xcode 27.0:

- **43 tests pass** (25 core, 10 viewer-model, 8 scroll-navigation). New cases cover single-line wheel ticks, rapid ticks, precise-event filtering, trackpad thresholds, one navigation per gesture, momentum, horizontal input, direction changes, smooth mice without phases, preference persistence/migration, canvas navigation, zoomed panning, and Option-scroll zoom.
- Optimized Xcode build and strict Swift formatting pass. The generated project includes the new input handler.
- Verified the Settings picker in the release app, enabled mouse-and-trackpad mode, and used automated UI scrolling to move forward and backward through generated images. Scrolling at 100% kept the selected image, and switching Off prevented navigation. Restored the original Off preference after testing.
- Physical trackpad and mouse feel still needs hands-on evaluation; automated gestures and synthetic event tests verify routing and gesture boundaries.


## ZIP / RAR / 7z archive milestone — September 18, 2026

- `swift test`: all 51 tests passed (18 app tests, 33 core tests). Covers RAR5 and 7z solid/independent fixtures, classic RAR4 solid headers, Unicode filenames, shared concurrent extraction, cache memory/disk budgets, cancellation, archive replacement, encrypted-file rejection, ZIP corruption/bounds, Deflate chunk boundaries, and sparse 512 MiB / 1 GiB directory offsets.
- `swift format lint --strict --recursive Sources Tests Package.swift`: passed.
- `python3 Scripts/generate-project.py` and `./Scripts/build.sh`: Release app built successfully on macOS 27.0 with Xcode 27.0. Upstream UnRAR sources emit existing C++ precision/parentheses warnings; the build has no errors.
- Ten synthetic large-archive runs completed: ~516 MiB and ~1026 MiB ZIP, non-solid and solid RAR5, and non-solid and solid 7z. Timing and peak RSS are recorded in `PERFORMANCE.md`, including the slower first deep jump in solid RAR and the conservative sequential 7z cache strategy.
- Manual built-app check: opened a solid RAR fixture, navigated to the next image with Command-Right, and opened a solid 7z fixture through the file picker. Both displayed four image entries, Unicode filenames, decoded dimensions, the correct selected image, and the archive title without errors. This is a basic interaction check, not a display-latency measurement.
- Large benchmark PNGs and archive files are generated only under `/tmp`, not included in the repository. Checked-in regression fixtures contain only generated small PNGs/text.

## Seamless image switching — September 18, 2026

Validated on macOS 27.0 / Xcode 27.0:

- **53 tests pass** (20 app tests, 33 core tests). New canvas regressions verify that uncached selections retain the previous pixels, zoom, and pan; repeated navigation still advances; replacement pixels and aspect ratio arrive together; cached previews replace the canvas while refinement is still loading; failures and empty selections clear retained pixels.
- Strict Swift formatting, project generation, the optimized Release build, and diff whitespace checks pass.
- Restarted the built app and exercised nine forward/three reverse selections through generated 24 MP JPEGs, immediate actual-size zoom and arrow panning, Command-arrow navigation, and return to Fit. Canvas content, filename, and sidebar selection agreed.
- This change removes the canvas clearing between selections. Decode time and physical input-to-display latency were not benchmarked for this change.
