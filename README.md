# Glint

A native, keyboard-first image viewer for modern Macs.

Glint is a fresh Swift reimplementation of the infamous Xee image viewer: open one image, browse its folder, and stay out of the way. It uses SwiftUI, AppKit, Image I/O, Core Animation, and Core Image. There is no web view, imported Objective-C application code, or bundled legacy decoder framework.

**Status: usable 0.1 foundation.** Fast folder browsing is the first priority. This is not yet a complete replacement for every Xee feature or historical format; [the feature inventory](docs/FEATURES.md) tracks that work explicitly.

## Run it

Requires an **Apple silicon Mac, macOS 26 or later, and Xcode 26 or later** (Swift 6.2+). Development builds have been verified locally with Xcode 27 / Swift 6.4 on macOS 27.

Open `Glint.xcodeproj`, choose **Glint → My Mac**, and press **Run**. The default signing identity is ad hoc; a developer account is not needed to build locally.

Or build the app from Terminal:

```sh
./Scripts/build.sh
open build/Build/Products/Release/Glint.app
```

For a quick development launch without Finder integration:

```sh
swift run Glint /path/to/images
```

Use the Xcode-built `.app` for Finder’s **Open With**, Dock, document icons, and normal application behavior. Release artifacts require Developer ID signing and notarization before public distribution; the local build is not notarized.

## What works

- Open images, folders, multiple selected files, ZIP/CBZ archives, and clipboard images. Drop files anywhere in the window.
- Natural filename sorting, date/size/type sorting, reverse order, filename filtering, optional recursive folders, and recent locations.
- Thumbnail sidebar and contact sheet with asynchronous, cached thumbnails.
- Next/previous, first/last, jumps of 10/100, random browsing with history, and optional looping.
- Fit, fill, actual pixels, pinch zoom, double-click zoom, drag/scroll panning, pixel interpolation, and four canvas backgrounds.
- Full screen, distraction-free view, timed/random slideshow, and display-sleep suppression during slideshows.
- EXIF-oriented decoding, metadata inspection, animated GIF/APNG/WebP when supported by Image I/O, frame stepping, multi-page TIFF, and PDF page navigation.
- Reversible rotation, flips, crop, undo/redo adjustments, and PNG/JPEG/HEIC/TIFF export.
- Rename, copy/move to a folder, move to Trash with confirmation, reveal in Finder, open in Preview, copy image, and print.
- Live updates for the open directory and selected file.

Format support comes from the installed macOS Image I/O decoders. This normally includes JPEG, PNG, HEIF/HEIC, GIF, TIFF, WebP, BMP, icons, and supported camera RAW files. Some specialized formats or variants are not supported; errors are shown without blocking navigation to the next file.

## Keyboard essentials

| Key | Action |
| --- | --- |
| Arrow keys | Browse if the image fits; pan if it overflows on that axis |
| Space / Shift Space / Backspace | Next / previous / previous image |
| ⌘ → / ⌘ ← | Next / previous at any zoom |
| Shift arrows / Option arrows | Jump 10 / 100 images |
| Home / End | First / last image |
| F / 1 | Fit / actual pixels |
| ⌘ ⌥ 0 / ⌘ 0 | Xee-style fit / actual pixels |
| + / − / pinch | Zoom |
| [ / ] | Previous / next frame or page |
| ⌘ F / ⌘ G / ⌘ I | Filter / contact sheet / information |
| ⌘ R / ⌘ ⇧ R | Rotate clockwise / counterclockwise |
| ⌘ K | Start crop; drag a rectangle, then Return to apply |
| ⌘ ⌥ Z / ⌘ ⌥ ⇧ Z | Undo / redo adjustment |
| ⌘ ⇧ S | Export |
| ⌘ ⌥ R | Refresh folder |
| ⌘ ⌥ S | Toggle slideshow |
| ⌘ ⌃ F / ⌘ ⇧ D | Full screen / distraction-free view |
| Escape | Cancel crop, stop slideshow, or leave full screen |
| ⌘ / | Show the shortcut reference |

At 100%, one source pixel occupies one display pixel, including on Retina displays. Small images stay at or below 100% in Fit unless enlargement is enabled in Settings.

## Data and editing

Browsing reads original files. Adjustments are temporary, belong to the current image, and reset when you navigate away. Export re-encodes the selected frame with adjustments; it does not perform lossless JPEG block transforms. Export omits source metadata and refuses the original path. The Copy Image and Print commands use the displayed rendition.

The app runs locally and has no analytics, network service, or automatic upload. It currently runs outside App Sandbox to support sibling browsing and file management. A sandboxed distribution will need security-scoped bookmarks and explicit folder-access handling.

ZIP/CBZ members are read directly into memory with size and CRC checks. No archive paths are extracted to disk. Encrypted archives, ZIP64, RAR/CBR, and 7z are not implemented. Viewing chooses a rendition for the window, normally 2048 pixels on the long edge, increasing up to 8192 for larger windows and high zoom; larger images remain downsampled. Full-resolution export is limited to 64 megapixels. PDF export is rasterized at a 4096-pixel long edge.

## Develop and verify

```sh
swift test
swift run -c release glint-bench /path/to/images 30
```

Generate reproducible samples for a smoke test:

```sh
swift Scripts/generate-fixtures.swift /tmp/Glint-Samples
open -a "$PWD/build/Build/Products/Release/Glint.app" /tmp/Glint-Samples
```

The Xcode project is checked in. Regenerate it after adding or removing app source files:

```sh
python3 Scripts/generate-project.py
```

The only C interface is a module map for **the system zlib**; all application, archive, and image handling logic is Swift. There are no remote Swift package dependencies.

See [architecture](docs/ARCHITECTURE.md), [performance methodology](docs/PERFORMANCE.md), [feature parity](docs/FEATURES.md), and [contributing](CONTRIBUTING.md). GitHub Actions builds an optimized app and runs the tests on macOS 26 when the repository is uploaded.

## License and inspiration

MIT, for the new code and artwork in this repository. Inspired by Xee’s folder-first workflow and the work of its original authors and maintainers. Xee source, graphics, bundled codecs, and frameworks are not redistributed here. See [acknowledgments](ACKNOWLEDGMENTS.md).
