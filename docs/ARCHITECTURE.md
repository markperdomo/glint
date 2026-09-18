# Architecture

Glint keeps the folder browser, decoding engine, and canvas separate. Swift 6 language mode checks concurrency boundaries. The UI targets macOS 26 APIs while remaining buildable with a newer SDK.

```text
SwiftUI scene / commands
        │
        ▼
ViewerModel (@MainActor, @Observable)
        ├── detached FolderScanner → immutable ImageCollection
        ├── viewer ImagePipeline actor → ImageDecoder → CGImage
        ├── thumbnail ImagePipeline actor → ImageDecoder → CGImage
        ├── Core Image adjustment rendering off the main actor
        └── AppKit ImageCanvas → Core Animation image layer
```

## Core package

- `ImageAsset` identifies filesystem images or archive members. Cache identity includes modification time and file size, not just filename.
- `FolderScanner` requests resource values in one pass, deduplicates selections, skips hidden files and packages, and checks cancellation during enumeration. UI work calls it from a detached task.
- `ImageDecoder` uses Image I/O thumbnails with orientation and immediate decode. It keeps original dimensions separately from the displayed rendition. PDF pages use Core Graphics. Metadata is converted into immutable value types.
- `ImagePipeline` is an actor with a cost-bounded LRU and a separate serial worker actor. Cache hits return while a miss is being decoded. Viewer and thumbnail pipelines have independent workers/caches, so thumbnails cannot fill the foreground decode queue. Cache budgets are 256 MiB and 48 MiB respectively, with an additional entry-count bound. Renditions use 1024/2048/4096/8192-pixel buckets based on the window and zoom.
- `ZIPArchive` parses the central directory in Swift, uses system zlib for raw Deflate, validates size and CRC, and returns member bytes. It never turns archive paths into extracted filesystem paths.
- `Viewport` is a pure geometry model. Its scale is display pixels per source pixel, making 100% accurate on Retina screens. A tolerance prevents a fitted image from accidentally becoming pannable.
- `ImageEditing` uses a reusable `CIContext` for transforms. Export decodes the source independently, applies the edit state, and writes a re-encoded image atomically.

`DecodedImage` is an explicitly unchecked Sendable container because `CGImage` is immutable. Core Image contexts are reused under the framework's thread-safety contract. AppKit objects remain on the main actor.

## UI and lifecycle

`ViewerModel` owns one browsing session. It holds stable IDs and an index map so ordinary navigation is constant-time. Filtering/sorting rebuild the visible array only when those settings or the collection change.

Opening a folder and loading an image have separate generation tokens. A canceled scan/decode can finish in the operating system, but its result cannot replace a newer selection. Adjacent-image prefetch submits one image at a time and cancels when selection changes. Queued actor work checks cancellation before decoding.

SwiftUI owns the sidebar, contact sheet, inspector, toolbar, sheets, settings, and menus. `ImageCanvas` is a small AppKit view with a persistent `CALayer`; pan/zoom changes geometry instead of redrawing image pixels. There is no custom Metal shader or texture-upload layer to maintain. Core Animation handles compositing and Core Image uses the system renderer for edits.

The canvas routes unmodified browse keys only in its own window and skips text editors and attached sheets. Command-arrow always navigates; ordinary arrows pan only when the relevant image axis overflows. Input uses the current model zoom mode immediately, without waiting for the next SwiftUI view update.

`FolderMonitor` watches the directory and selected file, coalescing notifications before rescanning. Refresh preserves the current identity where possible and moves to the next surviving entry after deletion. Subdirectory changes in recursive collections require a manual refresh for now.

## Platform references

- [Apple: Image I/O source decoding](https://developer.apple.com/documentation/imageio/cgimagesource)
- [Apple: immediate decode caching](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately)
- [Apple: adopting Liquid Glass through native controls](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Apple: CALayer dynamic range](https://developer.apple.com/documentation/quartzcore/calayer/preferreddynamicrange)

The current layer preference is not a claim of end-to-end HDR fidelity. Full HDR decode, gain-map preservation, high-bit-depth edits, and export need a dedicated validation corpus.
