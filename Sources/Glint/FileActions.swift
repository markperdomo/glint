import AppKit
import GlintCore
import SwiftUI
import UniformTypeIdentifiers

extension ViewerModel {
  func renameFile() {
    guard let asset = current, asset.isFile else { return }
    let alert = NSAlert()
    alert.messageText = "Rename Image"
    alert.informativeText = "Enter a new filename, including the extension."
    let field = NSTextField(string: asset.shortName)
    field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"),
      !name.contains("\0")
    else {
      errorMessage = "Enter a valid filename without slashes or colons."
      return
    }
    let destination = asset.url.deletingLastPathComponent().appendingPathComponent(name)
    guard destination != asset.url else { return }
    do {
      try FileManager.default.moveItem(at: asset.url, to: destination)
      open([destination])
    } catch { errorMessage = error.localizedDescription }
  }

  func trashFile() {
    guard let asset = current, asset.isFile else { return }
    let alert = NSAlert()
    alert.messageText = "Move “\(asset.shortName)” to the Trash?"
    alert.informativeText = "You can restore it from the Trash in Finder."
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
      refresh()
    } catch { errorMessage = error.localizedDescription }
  }

  func transferFile(move: Bool) {
    guard let asset = current, asset.isFile else { return }
    let panel = NSOpenPanel()
    panel.title = move ? "Move Image To" : "Copy Image To"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = move ? "Move" : "Copy"
    guard panel.runModal() == .OK, let directory = panel.url else { return }
    let destination = directory.appendingPathComponent(asset.shortName)
    // FileManager refuses collisions; an existing file is never silently replaced.
    Task {
      do {
        try await Task.detached(priority: .userInitiated) {
          if move {
            try FileManager.default.moveItem(at: asset.url, to: destination)
          } else {
            try FileManager.default.copyItem(at: asset.url, to: destination)
          }
        }.value
        if move { refresh() }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func openInPreview() {
    guard let asset = current else { return }
    guard asset.isFile else {
      errorMessage = "Export this archive image before opening it in another app."
      return
    }
    guard
      let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview")
    else { return }
    NSWorkspace.shared.open(
      [asset.url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration(),
      completionHandler: nil)
  }

  func copyImage() {
    guard let displayImage else { return }
    let image = NSImage(cgImage: displayImage, size: .zero)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
  }

  func pasteImage() {
    let pasteboard = NSPasteboard.general
    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
    {
      open(urls)
      return
    }
    guard let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation else {
      errorMessage = "The clipboard does not contain an image or file URL."
      return
    }
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Glint-Clipboard", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("Clipboard-\(UUID().uuidString.prefix(8)).tiff")
      try data.write(to: url, options: .atomic)
      open([url])
    } catch { errorMessage = error.localizedDescription }
  }

  func printImage() {
    guard let image = displayImage else { return }
    let view = NSImageView(frame: NSRect(x: 0, y: 0, width: image.width, height: image.height))
    view.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    view.imageScaling = .scaleProportionallyUpOrDown
    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
    info.horizontalPagination = .fit
    info.verticalPagination = .fit
    info.isHorizontallyCentered = true
    info.isVerticallyCentered = true
    NSPrintOperation(view: view, printInfo: info).run()
  }

  func export(format: ExportFormat, quality: Double) {
    guard let asset = current else { return }
    let panel = NSSavePanel()
    panel.title = "Export Image"
    panel.allowedContentTypes = [format.type]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue =
      (asset.shortName as NSString).deletingPathExtension + "-export." + format.fileExtension
    guard panel.runModal() == .OK, let url = panel.url else { return }
    // Never overwrite the original through the export workflow, including symlinks.
    guard
      url.resolvingSymlinksInPath().standardizedFileURL
        != asset.url.resolvingSymlinksInPath().standardizedFileURL
    else {
      errorMessage = "Choose a different filename to keep the original image intact."
      return
    }
    let edits = edits
    let frame = frameIndex
    isExporting = true
    Task {
      do {
        try await Task.detached(priority: .userInitiated) {
          try ImageEditing.export(
            asset, frame: frame, edits: edits, to: url, format: format, quality: quality)
        }.value
        isExporting = false
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } catch {
        isExporting = false
        errorMessage = error.localizedDescription
      }
    }
  }
}

struct ExportSheet: View {
  let model: ViewerModel
  @Environment(\.dismiss) private var dismiss
  @State private var format = ExportFormat.png
  @State private var quality = 0.92
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Make it yours.").font(.system(size: 28, design: .serif))
      Text("Export the current image or frame with your adjustments applied.")
        .font(.callout).foregroundStyle(.secondary)
      Form {
        Picker("Format", selection: $format) {
          ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
        }
        if format == .jpeg || format == .heic {
          HStack {
            Text("Quality")
            Slider(value: $quality, in: 0.1...1)
            Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 40)
          }
        }
      }
      Text(
        "Exports are re-encoded and omit source metadata. Your original stays intact. PDF pages export at up to 4096 pixels on the long edge."
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Choose Location…") {
          dismiss()
          Task { @MainActor in
            // Let the SwiftUI sheet dismiss before presenting an AppKit save panel.
            try? await Task.sleep(for: .milliseconds(250))
            model.export(format: format, quality: quality)
          }
        }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }.padding(28).frame(width: 430)
  }
}
