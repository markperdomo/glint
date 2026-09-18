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
