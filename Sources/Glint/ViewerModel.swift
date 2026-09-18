import AppKit
import GlintCore
import SwiftUI
import UniformTypeIdentifiers
import os

@MainActor @Observable
final class ViewerModel {
  let preferences: Preferences
  @ObservationIgnored private let pipeline: ImagePipeline
  @ObservationIgnored private let thumbnailPipeline: ImagePipeline
  @ObservationIgnored private var prediction = BrowsingPrediction()
  @ObservationIgnored private var navigationTrace: OSSignpostID?
  private static let performanceLog = OSLog(subsystem: "app.glint", category: "Navigation")
  private(set) var assets: [ImageAsset] = []
  private(set) var visibleAssets: [ImageAsset] = []
  private(set) var selectedID: String?
  private(set) var location: URL?
  private(set) var isArchive = false
  private(set) var decoded: DecodedImage?
  private(set) var displayImage: CGImage?
  private(set) var isLoading = false
  private(set) var isScanning = false
  var isExporting = false
  private(set) var loadError: String?
  var errorMessage: String?
  var query = "" { didSet { rebuildList() } }
  var sortOrder: ImageSortOrder = .name { didSet { rebuildList() } }
  var sortReversed = false { didSet { rebuildList() } }
  var recursive = false { didSet { if location != nil { refresh() } } }
  var sidebarVisible = true
  var inspectorVisible = false
  var zenMode = false
  var gridVisible = false
  var exportSheet = false
  var shortcutsVisible = false
  var searchFocusRequest = 0
  var zoomMode: ZoomMode = .fit
  var customZoom: CGFloat = 1
  var actualZoom: CGFloat = 1
  var panReset = 0
  var cropMode = false
  var cropSelection: CGRect?
  private(set) var edits = ImageEdits()
  private(set) var frameIndex = 0
  private(set) var animationPlaying = false
  private(set) var slideshowPlaying = false
  private(set) var recentURLs: [URL] = []

  @ObservationIgnored private var indices: [String: Int] = [:]
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var prefetchTask: Task<Void, Never>?
  @ObservationIgnored private var animationTask: Task<Void, Never>?
  @ObservationIgnored private var slideshowTask: Task<Void, Never>?
  @ObservationIgnored private var editTask: Task<Void, Never>?
  @ObservationIgnored private var scanGeneration = UUID()
  @ObservationIgnored private var loadGeneration = UUID()
  @ObservationIgnored private var editGeneration = UUID()
  @ObservationIgnored private var loadingDimension: Int?
  @ObservationIgnored private var canvasDimension = 2048
  @ObservationIgnored private var openedURLs: [URL] = []
  @ObservationIgnored private var history: [String] = []
  @ObservationIgnored private var editHistory: [ImageEdits] = []
  @ObservationIgnored private var redoHistory: [ImageEdits] = []
  @ObservationIgnored private var monitor = FolderMonitor()
  @ObservationIgnored private var activity: NSObjectProtocol?
  @ObservationIgnored weak var window: NSWindow?
  @ObservationIgnored var bringToFront: (() -> Void)?

  init(
    preferences: Preferences, pipeline: ImagePipeline = .shared,
    thumbnailPipeline: ImagePipeline = .thumbnails
  ) {
    self.preferences = preferences
    self.pipeline = pipeline
    self.thumbnailPipeline = thumbnailPipeline
    recentURLs = (UserDefaults.standard.stringArray(forKey: "recentPaths") ?? []).map {
      URL(fileURLWithPath: $0)
    }
  }

  var selectedIndex: Int? { selectedID.flatMap { indices[$0] } }
  var current: ImageAsset? { selectedIndex.map { visibleAssets[$0] } }
  var countLabel: String {
    selectedIndex.map { "\($0 + 1) of \(visibleAssets.count)" } ?? "\(visibleAssets.count) images"
  }
  var title: String { current?.shortName ?? "Glint" }
  var subtitle: String { location?.lastPathComponent ?? "" }
  var canUndo: Bool { !editHistory.isEmpty }
  var canRedo: Bool { !redoHistory.isEmpty }
  var canEdit: Bool { decoded != nil && !isLoading && !animationPlaying }
  var displayPixelSize: CGSize { edits.size(for: decoded?.metadata.pixelSize ?? .zero) }

  func openPanel() {
    let panel = NSOpenPanel()
    panel.title = "Open in Glint"
    panel.message =
      "Choose images, a folder, or a ZIP, RAR, or 7z archive. Opening one image also opens its folder."
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = true
    if panel.runModal() == .OK { open(panel.urls) }
  }

  func open(_ urls: [URL], refreshing: Bool = false) {
    guard !urls.isEmpty else { return }
    scanTask?.cancel()
    prefetchTask?.cancel()
    if !refreshing { stopSlideshow() }
    let generation = UUID()
    scanGeneration = generation
    isScanning = true
    let recurse = recursive
    let previous = refreshing ? selectedID : nil
    let previousIndex = selectedIndex ?? 0
    let previousAsset = current
    let work = Task.detached(priority: .userInitiated) {
      try FolderScanner.open(urls, recursive: recurse)
    }
    scanTask = Task { [weak self] in
      do {
        let collection = try await withTaskCancellationHandler {
          try await work.value
        } onCancel: {
          work.cancel()
        }
        guard let self, self.scanGeneration == generation, !Task.isCancelled else { return }
        self.isScanning = false
        self.location = collection.location
        self.isArchive = collection.isArchive
        self.openedURLs = urls.count == 1 && !collection.isArchive ? [collection.location] : urls
        if !refreshing {
          self.query = ""
          self.history.removeAll()
        }
        self.assets = collection.assets
        self.rebuildList(selectIfNeeded: false)
        let requested = previous ?? collection.initialID
        let id =
          requested.flatMap { self.indices[$0] != nil ? $0 : nil }
          ?? (self.visibleAssets.isEmpty
            ? nil : self.visibleAssets[min(previousIndex, self.visibleAssets.count - 1)].id)
        if refreshing, id == previous, let id,
          self.visibleAssets[self.indices[id]!] == previousAsset
        {
          self.updateWatch()
        } else {
          self.select(id, remember: false, force: true)
        }
        if !refreshing { self.addRecent(urls.count == 1 ? urls[0] : collection.location) }
        self.window?.representedURL = self.current?.url
      } catch is CancellationError {
      } catch {
        guard let self, self.scanGeneration == generation else { return }
        self.isScanning = false
        self.errorMessage = error.localizedDescription
      }
    }
  }

  func refresh() { open(openedURLs, refreshing: true) }

  private func rebuildList(selectIfNeeded: Bool = true) {
    let filtered =
      query.isEmpty ? assets : assets.filter { $0.name.localizedStandardContains(query) }
    visibleAssets = sortOrder.sorted(filtered, reversed: sortReversed)
    indices = Dictionary(
      uniqueKeysWithValues: visibleAssets.enumerated().map { ($0.element.id, $0.offset) })
    if selectIfNeeded, selectedID == nil || indices[selectedID!] == nil {
      select(visibleAssets.first?.id, remember: false)
    }
  }

  func select(
    _ id: String?, remember: Bool = true, force: Bool = false, navigationOffset: Int? = nil
  ) {
    guard id != selectedID || force else { return }
    if let navigationOffset {
      prediction.record(offset: navigationOffset)
    } else {
      prediction = BrowsingPrediction()
    }
    finishNavigationTrace("superseded")
    if id != nil {
      let trace = OSSignpostID(log: Self.performanceLog)
      navigationTrace = trace
      os_signpost(.begin, log: Self.performanceLog, name: "Selection to canvas", signpostID: trace)
    }
    if remember, let selectedID {
      history.append(selectedID)
      if history.count > 1000 { history.removeFirst() }
    }
    selectedID = id
    frameIndex = 0
    edits = ImageEdits()
    editHistory.removeAll()
    redoHistory.removeAll()
    cropMode = false
    cropSelection = nil
    editTask?.cancel()
    editGeneration = UUID()
    panReset += 1
    if !preferences.remembersZoom { zoomMode = .fit }
    loadCurrent()
    updateWatch()
    window?.representedURL = current?.url
  }

  func navigate(_ offset: Int) {
    guard
      let index = Navigation.index(
        from: selectedIndex ?? 0, offset: offset, count: visibleAssets.count,
        wraps: preferences.wraps)
    else { return }
    select(visibleAssets[index].id, navigationOffset: offset)
  }
  func first() { select(visibleAssets.first?.id) }
  func last() { select(visibleAssets.last?.id) }
  func random() {
    guard visibleAssets.count > 1 else { return }
    var next = Int.random(in: 0..<(visibleAssets.count - 1))
    if next >= (selectedIndex ?? 0) { next += 1 }
    select(visibleAssets[next].id)
  }
  func previousRandom() {
    while let id = history.popLast() {
      if indices[id] != nil {
        select(id, remember: false)
        return
      }
    }
  }
  func setZoom(_ mode: ZoomMode) {
    zoomMode = mode
    panReset += 1
    requestResolution()
  }
  func zoom(by factor: CGFloat) {
    let base = zoomMode == .custom ? customZoom : (zoomMode == .actual ? 1 : actualZoom)
    customZoom = min(32, max(0.01, base * factor))
    zoomMode = .custom
    requestResolution()
  }

  private var decodeDimension: Int {
    if zoomMode == .actual || (zoomMode == .custom && customZoom >= 1) { return 8192 }
    if zoomMode == .custom, let metadata = decoded?.metadata {
      return Self.dimensionBucket(
        CGFloat(max(metadata.pixelWidth, metadata.pixelHeight)) * customZoom)
    }
    if zoomMode == .fill { return max(4096, canvasDimension) }
    return canvasDimension
  }

  func updateCanvasDimension(_ pixels: CGFloat) {
    let dimension = Self.dimensionBucket(pixels)
    guard dimension != canvasDimension else { return }
    canvasDimension = dimension
    requestResolution()
  }

  private static func dimensionBucket(_ pixels: CGFloat) -> Int {
    [1024, 2048, 4096, 8192].first { CGFloat($0) >= pixels } ?? 8192
  }

  func requestResolution() {
    guard let current, let decoded, decodeDimension > (loadingDimension ?? 0),
      decodeDimension > max(decoded.image.width, decoded.image.height),
      max(decoded.metadata.pixelWidth, decoded.metadata.pixelHeight)
        > max(decoded.image.width, decoded.image.height)
    else { return }
    loadCurrent(preserving: true, asset: current)
  }

  private func loadCurrent(preserving: Bool = false, asset: ImageAsset? = nil) {
    loadTask?.cancel()
    prefetchTask?.cancel()
    stopAnimation()
    let generation = UUID()
    loadGeneration = generation
    loadError = nil
    guard let asset = asset ?? current else {
      decoded = nil
      displayImage = nil
      isLoading = false
      loadingDimension = nil
      return
    }
    if !preserving {
      // Publish identity, dimensions, and cached pixels in the same main-actor
      // turn. The canvas can hold its previous presentation during loading,
      // but model pixels and metadata must belong to the current selection.
      let candidates = [
        pipeline.cachedImage(for: asset, frame: frameIndex, maximumDimension: decodeDimension),
        thumbnailPipeline.cachedImage(
          for: asset, frame: frameIndex, maximumDimension: decodeDimension),
      ].compactMap { $0 }
      decoded = candidates.max {
        max($0.image.width, $0.image.height) < max($1.image.width, $1.image.height)
      }
      displayImage = decoded?.image
    }
    isLoading = true
    let dimension = decodeDimension
    loadingDimension = dimension
    let frame = frameIndex
    let rapid = !preserving && prediction.isRapid()
    let deadline = rapid ? prediction.settlingDeadline : nil
    let cachedDimension = decoded.map { max($0.image.width, $0.image.height) } ?? 0
    let needsPreview =
      !preserving
      && (decoded == nil || (rapid && cachedDimension < BrowsingPrediction.previewDimension))
    let pipeline = pipeline
    prefetchNeighbors(dimension: dimension, previewsOnly: rapid)
    loadTask = Task { [weak self] in
      do {
        if needsPreview {
          let preview = try await pipeline.image(
            for: asset, frame: frame, maximumDimension: BrowsingPrediction.previewDimension)
          guard let self, self.loadGeneration == generation, !Task.isCancelled else { return }
          self.decoded = preview
          self.renderEdits()
          os_signpost(.event, log: Self.performanceLog, name: "Preview ready")
        }
        if let deadline { try await ContinuousClock().sleep(until: deadline) }
        try Task.checkCancellation()
        let decoded = try await pipeline.image(
          for: asset, frame: frame, maximumDimension: dimension)
        guard let self, self.loadGeneration == generation, !Task.isCancelled else { return }
        self.decoded = decoded
        self.isLoading = false
        self.loadingDimension = nil
        self.renderEdits()
        os_signpost(.event, log: Self.performanceLog, name: "Rendition ready")
        self.prefetchNeighbors(dimension: dimension)
        if decoded.metadata.isAnimated && self.preferences.animatesImages && self.edits.isIdentity {
          self.startAnimation()
        }
        self.requestResolution()
      } catch is CancellationError {
      } catch {
        guard let self, self.loadGeneration == generation, !Task.isCancelled else { return }
        self.isLoading = false
        self.loadingDimension = nil
        self.loadError = error.localizedDescription
        self.finishNavigationTrace("failed")
      }
    }
  }

  private func prefetchNeighbors(dimension: Int, previewsOnly: Bool = false) {
    prefetchTask?.cancel()
    guard let index = selectedIndex else { return }
    var seen: Set<Int> = [index]
    let neighbors = prediction.offsets.compactMap {
      Navigation.index(
        from: index, offset: $0, count: visibleAssets.count, wraps: preferences.wraps)
    }.filter { seen.insert($0).inserted }.map { visibleAssets[$0] }
    let pipeline = pipeline
    // Keep cheap previews farther ahead, with window-sized pixels close by.
    // High zoom must not fill the cache with speculative 8192-pixel images.
    let neighborDimension = min(dimension, 4096)
    prefetchTask = Task(priority: .utility) {
      for asset in neighbors {
        guard !Task.isCancelled else { return }
        _ = try? await pipeline.image(
          for: asset, maximumDimension: BrowsingPrediction.previewDimension, priority: .prefetch)
      }
      guard !previewsOnly else { return }
      for asset in neighbors.prefix(2) {
        guard !Task.isCancelled else { return }
        _ = try? await pipeline.image(
          for: asset, maximumDimension: neighborDimension, priority: .prefetch)
      }
    }
  }

  /// Ends at CALayer submission, not physical display scanout. Pair these
  /// signposts with Core Animation's Instruments track to inspect presentation.
  func canvasDidSubmit(_ image: CGImage?) {
    guard let image, image === displayImage else { return }
    finishNavigationTrace("submitted")
  }

  private func finishNavigationTrace(_ outcome: String) {
    guard let trace = navigationTrace else { return }
    os_signpost(
      .end, log: Self.performanceLog, name: "Selection to canvas", signpostID: trace,
      "outcome=%{public}@", outcome)
    navigationTrace = nil
  }

  func stepFrame(_ offset: Int) {
    guard let decoded, decoded.metadata.frameCount > 1 else { return }
    stopAnimation()
    frameIndex =
      Navigation.index(
        from: frameIndex, offset: offset, count: decoded.metadata.frameCount, wraps: true) ?? 0
    // Loading a manually selected frame must not restart playback.
    loadFrameManually()
  }

  private func loadFrameManually() {
    guard let asset = current else { return }
    loadTask?.cancel()
    prefetchTask?.cancel()
    isLoading = true
    let generation = UUID()
    loadGeneration = generation
    let frame = frameIndex
    let dimension = decodeDimension
    let pipeline = pipeline
    loadTask = Task { [weak self] in
      do {
        let image = try await pipeline.image(
          for: asset, frame: frame, maximumDimension: dimension)
        guard let self, self.loadGeneration == generation, !Task.isCancelled else { return }
        self.decoded = image
        self.isLoading = false
        self.renderEdits()
      } catch is CancellationError {
      } catch {
        guard let self, self.loadGeneration == generation, !Task.isCancelled else { return }
        self.isLoading = false
        self.errorMessage = error.localizedDescription
      }
    }
  }

  func toggleAnimation() { animationPlaying ? stopAnimation() : startAnimation() }
  private func startAnimation() {
    guard let asset = current, let decoded, decoded.metadata.isAnimated, edits.isIdentity,
      !isLoading
    else { return }
    stopAnimation()
    animationPlaying = true
    let generation = loadGeneration
    let count = decoded.metadata.frameCount
    let dimension = canvasDimension
    animationTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        do {
          try await Task.sleep(for: .seconds(self.decoded?.frameDuration ?? 0.1))
          let frame = (self.frameIndex + 1) % count
          let next = try await self.pipeline.image(
            for: asset, frame: frame, maximumDimension: dimension)
          guard self.loadGeneration == generation, !Task.isCancelled else { return }
          self.frameIndex = frame
          self.decoded = next
          self.displayImage = next.image
        } catch is CancellationError {
          return
        } catch {
          self.stopAnimation()
          self.loadError = error.localizedDescription
          return
        }
      }
    }
  }
  func stopAnimation() {
    animationTask?.cancel()
    animationTask = nil
    animationPlaying = false
  }

  func toggleSlideshow() {
    if slideshowPlaying {
      stopSlideshow()
      return
    }
    guard visibleAssets.count > 1 else { return }
    slideshowPlaying = true
    activity = ProcessInfo.processInfo.beginActivity(
      options: [.idleDisplaySleepDisabled], reason: "Glint slideshow")
    slideshowTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        do { try await Task.sleep(for: .seconds(max(0.5, self.preferences.slideshowDelay))) } catch
        { return }
        guard !Task.isCancelled else { return }
        if self.isLoading { continue }
        if self.preferences.randomSlideshow {
          self.random()
        } else if !self.preferences.wraps && self.selectedIndex == self.visibleAssets.count - 1 {
          self.stopSlideshow()
          return
        } else {
          self.navigate(1)
        }
      }
    }
  }
  func stopSlideshow() {
    slideshowTask?.cancel()
    slideshowTask = nil
    slideshowPlaying = false
    if let activity {
      ProcessInfo.processInfo.endActivity(activity)
      self.activity = nil
    }
  }

  func changeEdits(_ change: (inout ImageEdits) -> Void) {
    guard canEdit else { return }
    editHistory.append(edits)
    redoHistory.removeAll()
    change(&edits)
    renderEdits()
    panReset += 1
  }
  func rotate(_ turns: Int) {
    changeEdits {
      $0.quarterTurns = ($0.quarterTurns + turns + 4) % 4
      $0.crop = nil
    }
  }
  func flip(horizontal: Bool) {
    changeEdits {
      if horizontal { $0.flipHorizontal.toggle() } else { $0.flipVertical.toggle() }
      $0.crop = nil
    }
  }
  func resetEdits() { changeEdits { $0 = ImageEdits() } }
  func undo() {
    guard let prior = editHistory.popLast() else { return }
    redoHistory.append(edits)
    edits = prior
    renderEdits()
  }
  func redo() {
    guard let next = redoHistory.popLast() else { return }
    editHistory.append(edits)
    edits = next
    renderEdits()
  }
  func applyCrop() {
    guard let selection = cropSelection, selection.width > 0.005, selection.height > 0.005 else {
      return
    }
    changeEdits { edits in
      let base = edits.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
      edits.crop = CGRect(
        x: base.minX + selection.minX * base.width, y: base.minY + selection.minY * base.height,
        width: selection.width * base.width, height: selection.height * base.height)
    }
    cropMode = false
    cropSelection = nil
    setZoom(.fit)
  }
  private func renderEdits() {
    editTask?.cancel()
    let generation = UUID()
    editGeneration = generation
    guard let decoded else { return }
    if edits.isIdentity {
      displayImage = decoded.image
      return
    }
    let edits = edits
    let work = Task.detached(priority: .userInitiated) {
      try ImageEditing.render(decoded.image, edits: edits)
    }
    editTask = Task { [weak self] in
      do {
        let image = try await work.value
        guard let self, self.editGeneration == generation, !Task.isCancelled else { return }
        self.displayImage = image
      } catch {
        guard let self, self.editGeneration == generation, !Task.isCancelled else { return }
        self.errorMessage = error.localizedDescription
      }
    }
  }

  private func updateWatch() {
    guard let location else {
      monitor.stop()
      return
    }
    monitor.watch([location] + (current.map { [$0.url] } ?? [])) { [weak self] in self?.refresh() }
  }
  private func addRecent(_ url: URL) {
    recentURLs.removeAll { $0 == url }
    recentURLs.insert(url, at: 0)
    recentURLs = Array(recentURLs.prefix(12))
    UserDefaults.standard.set(recentURLs.map(\.path), forKey: "recentPaths")
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
  }
  func clearRecent() {
    recentURLs = []
    UserDefaults.standard.removeObject(forKey: "recentPaths")
  }
  func reveal() {
    guard let current else { return }
    NSWorkspace.shared.activateFileViewerSelecting([current.url])
  }
  func toggleFullScreen() { window?.toggleFullScreen(nil) }
  func escape() {
    if cropMode {
      cropMode = false
      cropSelection = nil
    } else if slideshowPlaying {
      stopSlideshow()
    } else if zenMode {
      zenMode = false
    } else if window?.styleMask.contains(.fullScreen) == true {
      toggleFullScreen()
    }
  }
  func suspend() {
    stopAnimation()
    stopSlideshow()
    prefetchTask?.cancel()
    finishNavigationTrace("suspended")
    monitor.stop()
  }
  func resume() {
    updateWatch()
    if preferences.animatesImages { startAnimation() }
  }
}
