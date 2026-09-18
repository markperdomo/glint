import GlintCore
import SwiftUI

struct BrowserSidebar: View {
  @Bindable var model: ViewerModel
  @FocusState private var searchFocused: Bool
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: model.isArchive ? "archivebox" : "folder").foregroundStyle(.secondary)
          Text(model.location?.lastPathComponent ?? "Library").font(.headline).lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 0)
          Text("\(model.visibleAssets.count)").font(.caption).monospacedDigit().foregroundStyle(
            .secondary)
        }
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
          TextField("Filter images", text: $model.query).textFieldStyle(.plain).focused(
            $searchFocused
          )
          .accessibilityLabel("Filter images")
          .onExitCommand { searchFocused = false }
          if !model.query.isEmpty {
            Button {
              model.query = ""
            } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
          }
        }.font(.callout).padding(8).background(
          .quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
      }.padding(16)
      if model.assets.isEmpty {
        VStack(alignment: .leading, spacing: 14) {
          Label("FOLDERS, WITHOUT THE FUSS", systemImage: "sparkle").font(
            .system(size: 9, weight: .medium)
          ).tracking(1).foregroundStyle(.tertiary)
          Text("Open an image to explore everything beside it.").font(.callout).foregroundStyle(
            .secondary)
          Button("Open a Folder…") { model.openPanel() }
          Spacer()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ScrollViewReader { proxy in
          List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
            ForEach(model.visibleAssets) { asset in
              HStack(spacing: 10) {
                ThumbnailView(asset: asset).frame(width: 50, height: 46)
                  .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 4) {
                  Text(asset.shortName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .truncationMode(.middle)
                  HStack(spacing: 5) {
                    Text(asset.pathExtension.uppercased())
                    Text("·")
                    Text(
                      ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file))
                  }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, 3)
              .tag(asset.id).id(asset.id)
              .contextMenu {
                Button("Open Image") {
                  model.select(asset.id)
                  model.gridVisible = false
                }
                Button("Reveal in Finder") {
                  model.select(asset.id)
                  model.reveal()
                }
              }
            }
          }
          .listStyle(.sidebar)
          .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
        }
      }
      HStack {
        Menu {
          Picker("Sort by", selection: $model.sortOrder) {
            ForEach(ImageSortOrder.allCases) { Text($0.title).tag($0) }
          }
          Toggle("Reverse Order", isOn: $model.sortReversed)
          Divider()
          Toggle("Include Subfolders", isOn: $model.recursive).disabled(model.isArchive)
        } label: {
          Label(model.sortOrder.title, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton).fixedSize()
        Spacer()
        Button {
          model.refresh()
        } label: {
          Image(systemName: "arrow.clockwise")
        }.buttonStyle(.plain).help("Refresh folder (⌘⌥R)")
      }.font(.caption).foregroundStyle(.secondary).padding(14)
    }
    .onChange(of: model.searchFocusRequest) { searchFocused = true }
  }
}

struct ThumbnailView: View {
  let asset: ImageAsset
  var dimension = 160
  @State private var image: CGImage?
  @State private var failed = false
  var body: some View {
    ZStack {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        Image(systemName: failed ? "photo.badge.exclamationmark" : "photo").font(.title3)
          .foregroundStyle(.tertiary)
      }
    }
    .clipShape(.rect(cornerRadius: 4))
    .accessibilityHidden(true)
    .task(id: asset) {
      image = nil
      failed = false
      do {
        let decoded = try await ImagePipeline.thumbnails.image(
          for: asset, maximumDimension: dimension)
        guard !Task.isCancelled else { return }
        image = decoded.image
      } catch is CancellationError {
      } catch { failed = true }
    }
  }
}

struct ContactSheet: View {
  let model: ViewerModel
  var body: some View {
    ScrollView {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20)], spacing: 24
      ) {
        ForEach(model.visibleAssets) { asset in
          Button {
            model.select(asset.id)
            model.gridVisible = false
          } label: {
            VStack(spacing: 10) {
              ThumbnailView(asset: asset, dimension: 400).frame(height: 130)
                .frame(maxWidth: .infinity).background(
                  .quaternary.opacity(0.25), in: .rect(cornerRadius: 8)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 8).strokeBorder(
                    model.selectedID == asset.id ? Color.accentColor : .clear, lineWidth: 2))
              Text(asset.shortName).font(.caption).lineLimit(1).truncationMode(.middle)
            }
          }.buttonStyle(.plain)
        }
      }.padding(28)
    }
    .background(.background)
  }
}
