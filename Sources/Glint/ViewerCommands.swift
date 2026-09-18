import GlintCore
import SwiftUI

struct ViewerCommands: Commands {
  @Bindable var model: ViewerModel
  @Environment(\.openWindow) private var openWindow
  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Open…") {
        openWindow(id: "viewer")
        model.openPanel()
      }.keyboardShortcut("o")
      Menu("Open Recent") {
        ForEach(model.recentURLs, id: \.self) { url in
          Button(url.lastPathComponent) {
            openWindow(id: "viewer")
            model.open([url])
          }
        }
        Divider()
        Button("Clear Menu") { model.clearRecent() }
      }
      Button("Open from Clipboard") {
        openWindow(id: "viewer")
        model.pasteImage()
      }.keyboardShortcut("v", modifiers: [.command, .shift])
    }
    // Keep the standard Close command (⌘W), which is part of the save group.
    CommandGroup(after: .saveItem) {
      Button("Export…") { model.exportSheet = true }.keyboardShortcut(
        "s", modifiers: [.command, .shift]
      ).disabled(!model.canEdit)
      Divider()
      Button("Reveal in Finder") { model.reveal() }.keyboardShortcut(
        "f", modifiers: [.command, .shift]
      ).disabled(model.current == nil)
      Button("Open in Preview") { model.openInPreview() }.keyboardShortcut("e").disabled(
        model.current == nil)
      Divider()
      Button("Rename…") { model.renameFile() }.disabled(model.current?.isFile != true)
      Button("Copy File To…") { model.transferFile(move: false) }.keyboardShortcut(
        "c", modifiers: [.command, .shift]
      ).disabled(model.current?.isFile != true)
      Button("Move File To…") { model.transferFile(move: true) }.keyboardShortcut(
        "m", modifiers: [.command, .shift]
      ).disabled(model.current?.isFile != true)
      Button("Move to Trash…") { model.trashFile() }.keyboardShortcut(.delete, modifiers: .command)
        .disabled(model.current?.isFile != true)
    }
    CommandGroup(replacing: .printItem) {
      Button("Print…") { model.printImage() }.keyboardShortcut("p").disabled(
        model.displayImage == nil)
    }
    CommandGroup(after: .pasteboard) {
      Divider()
      Button("Copy Image") { model.copyImage() }.keyboardShortcut(
        "c", modifiers: [.command, .option]
      ).disabled(model.displayImage == nil)
    }
    CommandMenu("Browse") {
      Button("Next Image") { model.navigate(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
      Button("Previous Image") { model.navigate(-1) }.keyboardShortcut(
        .leftArrow, modifiers: .command)
      Button("First Image") { model.first() }.keyboardShortcut(
        .leftArrow, modifiers: [.command, .shift])
      Button("Last Image") { model.last() }.keyboardShortcut(
        .rightArrow, modifiers: [.command, .shift])
      Divider()
      Button("10 Images Forward") { model.navigate(10) }
      Button("10 Images Back") { model.navigate(-10) }
      Button("100 Images Forward") { model.navigate(100) }
      Button("100 Images Back") { model.navigate(-100) }
      Divider()
      Button("Random Image") { model.random() }.keyboardShortcut(
        "r", modifiers: [.command, .control])
      Button("Previous Random Image") { model.previousRandom() }
      Toggle(
        "Loop Images",
        isOn: Binding(get: { model.preferences.wraps }, set: { model.preferences.wraps = $0 }))
      Menu("Sort Order") {
        Picker("Sort by", selection: $model.sortOrder) {
          ForEach(ImageSortOrder.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Reverse Order", isOn: $model.sortReversed)
      }
      Toggle("Include Subfolders", isOn: $model.recursive).disabled(model.isArchive)
      Button("Refresh Folder") { model.refresh() }.keyboardShortcut(
        "r", modifiers: [.command, .option])
      Divider()
      Button(model.slideshowPlaying ? "Stop Slideshow" : "Start Slideshow") {
        model.toggleSlideshow()
      }.keyboardShortcut("s", modifiers: [.command, .option])
    }
    CommandMenu("Image") {
      Button("Rotate Clockwise") { model.rotate(1) }.keyboardShortcut("r").disabled(!model.canEdit)
      Button("Rotate Counterclockwise") { model.rotate(-1) }.keyboardShortcut(
        "r", modifiers: [.command, .shift]
      ).disabled(!model.canEdit)
      Button("Rotate 180°") { model.rotate(2) }.disabled(!model.canEdit)
      Button("Flip Horizontal") { model.flip(horizontal: true) }.disabled(!model.canEdit)
      Button("Flip Vertical") { model.flip(horizontal: false) }.disabled(!model.canEdit)
      Button("Crop…") { model.cropMode.toggle() }.keyboardShortcut("k").disabled(!model.canEdit)
      Button("Reset Adjustments") { model.resetEdits() }.disabled(
        !model.canEdit || model.edits.isIdentity)
      Divider()
      Button("Undo Adjustment") { model.undo() }.keyboardShortcut(
        "z", modifiers: [.command, .option]
      ).disabled(!model.canUndo)
      Button("Redo Adjustment") { model.redo() }.keyboardShortcut(
        "z", modifiers: [.command, .option, .shift]
      ).disabled(!model.canRedo)
      Divider()
      Button("Previous Frame / Page") { model.stepFrame(-1) }.keyboardShortcut(
        "[", modifiers: .command
      ).disabled((model.decoded?.metadata.frameCount ?? 1) < 2)
      Button("Next Frame / Page") { model.stepFrame(1) }.keyboardShortcut("]", modifiers: .command)
        .disabled((model.decoded?.metadata.frameCount ?? 1) < 2)
      Button(model.animationPlaying ? "Pause Animation" : "Play Animation") {
        model.toggleAnimation()
      }.disabled(model.decoded?.metadata.isAnimated != true)
    }
    CommandGroup(after: .toolbar) {
      Button("Fit to Window") { model.setZoom(.fit) }.keyboardShortcut(
        "0", modifiers: [.command, .option])
      Button("Actual Pixels") { model.setZoom(.actual) }.keyboardShortcut("0")
      Button("Fill Window") { model.setZoom(.fill) }.keyboardShortcut("9")
      Button("Zoom In") { model.zoom(by: 1.25) }.keyboardShortcut("+")
      Button("Zoom Out") { model.zoom(by: 0.8) }.keyboardShortcut("-")
      Divider()
      Button("Filter Images") {
        model.sidebarVisible = true
        model.searchFocusRequest += 1
      }.keyboardShortcut("f")
      Toggle("Contact Sheet", isOn: $model.gridVisible).keyboardShortcut("g")
      Toggle("Image Information", isOn: $model.inspectorVisible).keyboardShortcut("i")
      Toggle("Distraction-Free View", isOn: $model.zenMode).keyboardShortcut(
        "d", modifiers: [.command, .shift])
      Button("Toggle Full Screen") { model.toggleFullScreen() }.keyboardShortcut(
        "f", modifiers: [.command, .control])
    }
    CommandGroup(replacing: .help) {
      Button("Keyboard Shortcuts") { model.shortcutsVisible = true }.keyboardShortcut(
        "/", modifiers: .command)
    }
  }
}

struct ShortcutsView: View {
  @Environment(\.dismiss) private var dismiss
  private let shortcuts = [
    ("← / → / ↑ / ↓", "Browse, or pan an overflowing image"),
    ("Space / Shift Space", "Next / previous image"),
    ("⌘ → / ⌘ ←", "Browse at any zoom level"),
    ("Shift arrows / Option arrows", "Jump 10 / 100 images"),
    ("Home / End", "First / last image"),
    ("F / 1", "Fit to window / actual pixels"),
    ("+ / − / pinch", "Zoom in / out"),
    ("Double-click", "Toggle fit and actual pixels"),
    ("[ / ]", "Previous / next frame or PDF page"),
    ("⌘ F / ⌘ G / ⌘ I", "Filter / contact sheet / inspector"),
    ("⌘ R / ⌘ ⇧ R", "Rotate clockwise / counterclockwise"),
    ("⌘ K / Return / Escape", "Crop / apply / cancel"),
    ("⌘ ⌥ Z / ⌘ ⌥ ⇧ Z", "Undo / redo an adjustment"),
    ("⌘ ⇧ S", "Export an image"),
    ("⌘ ⌥ S", "Start / stop slideshow"),
    ("Escape", "Stop slideshow or leave full screen"),
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
      Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
        ForEach(shortcuts, id: \.0) { key, action in
          GridRow {
            Text(key).font(.system(size: 11, weight: .medium, design: .monospaced))
            Text(action).font(.callout).foregroundStyle(.secondary)
          }
        }
      }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(28).frame(width: 630)
  }
}
