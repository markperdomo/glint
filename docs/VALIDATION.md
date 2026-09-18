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
