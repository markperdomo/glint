import GlintCore
import SwiftUI

struct ContentView: View {
  @Bindable var model: ViewerModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    NavigationSplitView(
      columnVisibility: Binding(
        get: { model.sidebarVisible && !model.zenMode ? .all : .detailOnly },
        set: { model.sidebarVisible = $0 != .detailOnly }
      )
    ) {
      BrowserSidebar(model: model)
        .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 380)
    } detail: {
      VStack(spacing: 0) {
        ZStack {
          if model.location == nil {
            WelcomeView(model: model)
          } else if model.gridVisible {
            ContactSheet(model: model)
          } else {
            CanvasView(model: model)
            if let error = model.loadError {
              ContentUnavailableView {
                Label("Couldn’t display this image", systemImage: "photo.badge.exclamationmark")
              } description: {
                Text(error).frame(maxWidth: 430)
              } actions: {
                Button("Next Image") { model.navigate(1) }
              }.environment(\.colorScheme, .dark)
            } else if model.visibleAssets.isEmpty && !model.isScanning {
              ContentUnavailableView(
                model.query.isEmpty ? "No images in this folder" : "No matching images",
                systemImage: "photo.on.rectangle.angled",
                description: Text(
                  model.query.isEmpty
                    ? "Try including subfolders or open another folder."
                    : "Try a different filename.")
              )
              .environment(\.colorScheme, .dark)
            }
            LoadingBadge(loading: model.isLoading || model.isScanning)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          if model.cropMode { cropBar.padding(.bottom, 20) }
        }
        if !model.zenMode { StatusBar(model: model) }
      }
      .navigationTitle(model.title)
      .navigationSubtitle(model.subtitle)
      .toolbar { toolbar }
    }
    .inspector(isPresented: $model.inspectorVisible) {
      InspectorView(model: model).inspectorColumnWidth(min: 240, ideal: 280, max: 380)
    }
    .frame(minWidth: 760, minHeight: 480)
    .tint(Color(red: 0.40, green: 0.48, blue: 0.27))
    .dropDestination(for: URL.self) { urls, _ in
      let files = urls.filter(\.isFileURL)
      guard !files.isEmpty else { return false }
      model.open(files)
      return true
    }
    .alert(
      "Glint",
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .sheet(isPresented: $model.exportSheet) { ExportSheet(model: model) }
    .sheet(isPresented: $model.shortcutsVisible) { ShortcutsView() }
    .background(WindowBridge(model: model).frame(width: 0, height: 0))
    .onAppear {
      model.bringToFront = { openWindow(id: "viewer") }
      model.resume()
    }
    .onDisappear { model.suspend() }
    .onChange(of: model.preferences.animatesImages) { _, play in
      if play && !model.animationPlaying {
        model.toggleAnimation()
      } else if !play {
        model.stopAnimation()
      }
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Button {
        model.openPanel()
      } label: {
        Label("Open", systemImage: "folder")
      }.help("Open images or a folder (⌘O)")
    }
    ToolbarItemGroup(placement: .navigation) {
      Button {
        model.navigate(-1)
      } label: {
        Label("Previous Image", systemImage: "chevron.left")
      }
      .disabled(model.visibleAssets.count < 2)
      Button {
        model.navigate(1)
      } label: {
        Label("Next Image", systemImage: "chevron.right")
      }
      .disabled(model.visibleAssets.count < 2)
    }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Button("Fit to Window") { model.setZoom(.fit) }
        Button("Actual Pixels (100%)") { model.setZoom(.actual) }
        Button("Fill Window") { model.setZoom(.fill) }
        Divider()
        Button("Zoom In") { model.zoom(by: 1.25) }
        Button("Zoom Out") { model.zoom(by: 0.8) }
      } label: {
        Text(model.zoomMode == .fit ? "Fit" : "\(Int(model.actualZoom * 100))%")
          .monospacedDigit().frame(minWidth: 32)
      }.help("Zoom — F to fit, 1 for actual pixels")
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        model.toggleSlideshow()
      } label: {
        Label(
          model.slideshowPlaying ? "Stop Slideshow" : "Start Slideshow",
          systemImage: model.slideshowPlaying ? "pause.fill" : "play.fill")
      }.disabled(model.visibleAssets.count < 2)
    }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      Button {
        model.gridVisible.toggle()
      } label: {
        Label("Contact Sheet", systemImage: model.gridVisible ? "rectangle" : "square.grid.2x2")
      }
      .disabled(model.assets.isEmpty).help("Toggle contact sheet (⌘G)")
    }
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Button("Rotate Clockwise", systemImage: "rotate.right") { model.rotate(1) }
        Button("Rotate Counterclockwise", systemImage: "rotate.left") { model.rotate(-1) }
        Button(
          "Flip Horizontal",
          systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        ) { model.flip(horizontal: true) }
        Button("Flip Vertical") { model.flip(horizontal: false) }
        Button("Crop…", systemImage: "crop") { model.cropMode.toggle() }
        Divider()
        Button("Reset Adjustments") { model.resetEdits() }.disabled(model.edits.isIdentity)
        Divider()
        Button("Export…", systemImage: "square.and.arrow.up") { model.exportSheet = true }
      } label: {
        Label("Image Actions", systemImage: "slider.horizontal.3")
      }
      .disabled(!model.canEdit)
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        model.inspectorVisible.toggle()
      } label: {
        Label("Image Information", systemImage: "info.circle")
      }
      .help("Show image information (⌘I)")
    }
  }

  private var cropBar: some View {
    HStack(spacing: 16) {
      Label("Drag to select a crop", systemImage: "crop").font(.callout)
      Button("Cancel") {
        model.cropMode = false
        model.cropSelection = nil
      }
      Button("Apply Crop") { model.applyCrop() }.buttonStyle(.borderedProminent).disabled(
        model.cropSelection == nil)
    }
    .padding(12).glassEffect(in: .rect(cornerRadius: 16))
  }
}

private struct WindowBridge: NSViewRepresentable {
  let model: ViewerModel
  func makeNSView(context: Context) -> BridgeView {
    let view = BridgeView()
    view.model = model
    return view
  }
  func updateNSView(_ nsView: BridgeView, context: Context) {}
  final class BridgeView: NSView {
    weak var model: ViewerModel?
    override func viewDidMoveToWindow() { model?.window = window }
  }
}

private struct LoadingBadge: View {
  let loading: Bool
  @State private var visible = false
  var body: some View {
    VStack {
      Spacer()
      if visible {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text("Loading…").font(.callout)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).glassEffect().padding(.bottom, 20)
      }
    }.allowsHitTesting(false)
      .task(id: loading) {
        visible = false
        guard loading else { return }
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        visible = true
      }
  }
}

private struct StatusBar: View {
  let model: ViewerModel
  var body: some View {
    HStack(spacing: 16) {
      if model.isScanning { ProgressView().controlSize(.mini) }
      Text(model.countLabel).monospacedDigit()
      if let metadata = model.decoded?.metadata {
        Divider().frame(height: 12)
        Text("\(metadata.pixelWidth) × \(metadata.pixelHeight)").monospacedDigit()
        if let asset = model.current {
          Text(ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file))
            .foregroundStyle(.tertiary)
        }
        Spacer()
        if !model.edits.isIdentity { Label("Adjusted", systemImage: "slider.horizontal.3") }
        if metadata.frameCount > 1 {
          Button {
            model.stepFrame(-1)
          } label: {
            Image(systemName: "backward.end")
          }
          Text("\(model.frameIndex + 1) / \(metadata.frameCount)").monospacedDigit()
          Button {
            model.stepFrame(1)
          } label: {
            Image(systemName: "forward.end")
          }
          if metadata.isAnimated {
            Button {
              model.toggleAnimation()
            } label: {
              Image(systemName: model.animationPlaying ? "pause" : "play")
            }
          }
        }
        Text("\(Int(model.actualZoom * 100))%").monospacedDigit()
      } else {
        Spacer()
      }
      if model.slideshowPlaying { Label("Slideshow", systemImage: "play.fill") }
    }
    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
    .padding(.horizontal, 16).frame(height: 32)
    .background(.bar)
  }
}
