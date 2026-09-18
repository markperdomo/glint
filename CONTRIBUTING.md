# Contributing

Start with [the feature inventory](docs/FEATURES.md). Everyday folder browsing takes priority over adding a large dependency or recreating obsolete UI.

Use Swift 6 concurrency checking. Keep file enumeration and image decoding off the main actor. Preserve cancellation, bounded caches, and stable selection identity. New decoders belong behind `GlintCore`; their failures must not break navigation to other images.

For changes to archive parsing, geometry, cache behavior, file selection, or export, add a focused regression test with generated or redistributable fixtures. Never check in private photos, archives, credentials, or developer signing identities.

Before submitting:

```sh
swift test
swift format lint --strict --recursive Sources Tests Package.swift
python3 Scripts/generate-project.py
./Scripts/build.sh
git diff --check
```

Manually exercise the changed interaction in the `.app`. Report the macOS/Xcode versions and distinguish measured performance from assumptions. Keep the README and feature inventory honest about limitations.

The app icon is original vector drawing code in `Scripts/generate-icon.swift`; its generated PNGs are checked in so building does not require an asset-generation step.
