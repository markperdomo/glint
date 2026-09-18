import AppKit
import GlintCore
import QuartzCore
import SwiftUI

struct CanvasView: NSViewRepresentable {
  let model: ViewerModel
  func makeNSView(context: Context) -> ImageCanvas {
    let view = ImageCanvas()
    view.model = model
    return view
  }
  func updateNSView(_ view: ImageCanvas, context: Context) {
    view.model = model
    // Explicit reads make Observation invalidate this representable for changes.
    view.update(
      image: model.displayImage, pixels: model.displayPixelSize,
      zoom: model.zoomMode, custom: model.customZoom, reset: model.panReset,
      background: model.preferences.background, nearest: model.preferences.nearestNeighbor,
      enlarges: model.preferences.enlargesSmallImages, cropping: model.cropMode)
  }
}

@MainActor
final class ImageCanvas: NSView {
  weak var model: ViewerModel?
  private let imageLayer = CALayer()
  private let cropLayer = CAShapeLayer()
  private var pixelSize = CGSize.zero
  private var mode = ZoomMode.fit
  private var custom: CGFloat = 1
  private var enlarges = true
  private var pan = CGPoint.zero
  private var reset = -1
  private var imageRect = CGRect.zero
  private var dragStart = CGPoint.zero
  private var dragPan = CGPoint.zero
  private var cropStart: CGPoint?
  private var isCropping = false
  private var lastScroll: TimeInterval = 0
  private var monitor: Any?
  private var background = CanvasBackground.charcoal
  private static let checker = NSColor(
    patternImage: NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
      NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
      rect.fill()
      NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
      NSRect(x: 0, y: 0, width: 10, height: 10).fill()
      NSRect(x: 10, y: 10, width: 10, height: 10).fill()
      return true
    })

  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { true }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    imageLayer.contentsGravity = .resize
    imageLayer.minificationFilter = .trilinear
    imageLayer.preferredDynamicRange = .high
    imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    layer?.addSublayer(imageLayer)
    cropLayer.strokeColor = NSColor.white.cgColor
    cropLayer.fillColor = NSColor.white.withAlphaComponent(0.12).cgColor
    cropLayer.lineWidth = 1.5
    cropLayer.lineDashPattern = [6, 4]
    layer?.addSublayer(cropLayer)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Image canvas")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    guard let window else { return }
    model?.window = window
    window.makeFirstResponder(self)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.window, self.window?.attachedSheet == nil,
        !(self.window?.firstResponder is NSTextView),
        !(self.window?.firstResponder is NSTextField)
      else { return event }
      return self.handleKey(event) ? nil : event
    }
  }
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    needsLayout = true
  }

  func update(
    image: CGImage?, pixels: CGSize, zoom: ZoomMode, custom: CGFloat, reset: Int,
    background: CanvasBackground, nearest: Bool, enlarges: Bool, cropping: Bool
  ) {
    if self.reset != reset {
      pan = .zero
      self.reset = reset
      cropLayer.path = nil
    }
    imageLayer.contents = image
    imageLayer.magnificationFilter = nearest ? .nearest : .linear
    imageLayer.isHidden = image == nil
    pixelSize = pixels
    mode = zoom
    self.custom = custom
    self.enlarges = enlarges
    if self.background != background {
      self.background = background
      needsDisplay = true
    }
    isCropping = cropping
    if !cropping { cropLayer.path = nil }
    setAccessibilityValue(model?.current?.shortName ?? "No image")
    needsLayout = true
  }

  private var viewport: Viewport {
    Viewport(
      viewport: bounds.insetBy(dx: 16, dy: 16).size, pixels: pixelSize,
      backingScale: window?.backingScaleFactor ?? 2, mode: model?.zoomMode ?? mode,
      customScale: model?.customZoom ?? custom, enlargesSmallImages: enlarges)
  }

  override func layout() {
    super.layout()
    let viewport = viewport
    pan = viewport.clampedPan(pan)
    let size = viewport.displaySize
    imageRect = CGRect(
      x: (bounds.width - size.width) / 2 + pan.x, y: (bounds.height - size.height) / 2 + pan.y,
      width: size.width, height: size.height)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    imageLayer.frame = imageRect
    CATransaction.commit()
    let scale = viewport.scale
    let backing = window?.backingScaleFactor ?? 2
    let neededPixels = max(bounds.width, bounds.height) * backing
    Task { @MainActor [weak model] in model?.updateCanvasDimension(neededPixels) }
    if let model, abs(model.actualZoom - scale) > 0.0001 {
      Task { @MainActor [weak model] in model?.actualZoom = scale }
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    let color: NSColor =
      switch background {
      case .charcoal: NSColor(calibratedWhite: 0.075, alpha: 1)
      case .black: .black
      case .white: .white
      case .checkerboard: Self.checker
      }
    color.setFill()
    dirtyRect.fill()
  }
  override func resetCursorRects() {
    addCursorRect(
      bounds,
      cursor: isCropping
        ? .crosshair
        : (viewport.canPanHorizontally || viewport.canPanVertically ? .openHand : .arrow))
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    if isCropping {
      guard imageRect.contains(point) else { return }
      cropStart = point
    } else if event.clickCount == 2 {
      model?.setZoom(model?.zoomMode == .fit ? .actual : .fit)
    } else {
      dragStart = point
      dragPan = pan
      if viewport.canPanHorizontally || viewport.canPanVertically { NSCursor.closedHand.push() }
    }
  }
  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if isCropping, let start = cropStart {
      let rect = CGRect(
        x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x),
        height: abs(point.y - start.y)
      ).intersection(imageRect)
      guard !rect.isNull, imageRect.width > 0, imageRect.height > 0 else { return }
      cropLayer.path = CGPath(rect: rect, transform: nil)
      model?.cropSelection = CGRect(
        x: (rect.minX - imageRect.minX) / imageRect.width,
        y: (rect.minY - imageRect.minY) / imageRect.height,
        width: rect.width / imageRect.width, height: rect.height / imageRect.height)
    } else {
      pan = viewport.clampedPan(
        CGPoint(x: dragPan.x + point.x - dragStart.x, y: dragPan.y + point.y - dragStart.y))
      needsLayout = true
    }
  }
  override func mouseUp(with event: NSEvent) {
    cropStart = nil
    if NSCursor.current == .closedHand { NSCursor.pop() }
  }
  override func magnify(with event: NSEvent) { model?.zoom(by: 1 + event.magnification) }
  override func smartMagnify(with event: NSEvent) {
    model?.setZoom(model?.zoomMode == .fit ? .actual : .fit)
  }
  override func scrollWheel(with event: NSEvent) {
    if event.modifierFlags.contains(.option) {
      model?.zoom(by: pow(1.015, event.scrollingDeltaY))
      return
    }
    if viewport.canPanHorizontally || viewport.canPanVertically {
      let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
      pan = viewport.clampedPan(
        CGPoint(
          x: pan.x + event.scrollingDeltaX * multiplier,
          y: pan.y - event.scrollingDeltaY * multiplier))
      needsLayout = true
    } else if model?.preferences.scrollToBrowse == true, abs(event.scrollingDeltaY) > 1,
      event.timestamp - lastScroll > 0.18, event.momentumPhase.isEmpty
    {
      lastScroll = event.timestamp
      model?.navigate(event.scrollingDeltaY < 0 ? 1 : -1)
    }
  }

  @objc func copy(_ sender: Any?) { model?.copyImage() }

  func handleKey(_ event: NSEvent) -> Bool {
    guard let model else { return false }
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if modifiers.contains(.command) || modifiers.contains(.control) { return false }
    let horizontal = event.keyCode == 123 || event.keyCode == 124
    let vertical = event.keyCode == 125 || event.keyCode == 126
    if horizontal || vertical {
      let forward = event.keyCode == 124 || event.keyCode == 125
      if modifiers.contains(.option) {
        model.navigate(forward ? 100 : -100)
      } else if modifiers.contains(.shift) {
        model.navigate(forward ? 10 : -10)
      } else if (horizontal && viewport.canPanHorizontally)
        || (vertical && viewport.canPanVertically)
      {
        if horizontal { pan.x += forward ? -80 : 80 } else { pan.y += forward ? 80 : -80 }
        pan = viewport.clampedPan(pan)
        needsLayout = true
      } else {
        model.navigate(forward ? 1 : -1)
      }
      return true
    }
    switch event.keyCode {
    case 49: model.navigate(modifiers.contains(.shift) ? -1 : 1)
    case 51: model.navigate(-1)
    case 115: model.first()
    case 119: model.last()
    case 116: model.navigate(-1)
    case 121: model.navigate(1)
    case 53: model.escape()
    case 36 where model.cropMode: model.applyCrop()
    default:
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "f": model.setZoom(.fit)
      case "1": model.setZoom(.actual)
      case "+", "=": model.zoom(by: 1.25)
      case "-": model.zoom(by: 0.8)
      case "[": model.stepFrame(-1)
      case "]": model.stepFrame(1)
      default: return false
      }
    }
    return true
  }
}
