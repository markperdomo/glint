import GlintCore
import SwiftUI

struct InspectorView: View {
  let model: ViewerModel
  var body: some View {
    if let asset = model.current, let metadata = model.decoded?.metadata {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text("IMAGE INFORMATION").font(.system(size: 9, weight: .medium)).tracking(1.5)
              .foregroundStyle(.secondary)
            Text(asset.shortName).font(.title3.weight(.medium)).textSelection(.enabled)
            Text(metadata.format).font(.callout).foregroundStyle(.secondary)
          }
          VStack(spacing: 14) {
            infoRow("Dimensions", "\(metadata.pixelWidth) × \(metadata.pixelHeight)")
            infoRow(
              "Size", ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file))
            infoRow("Color profile", metadata.colorSpace)
            infoRow("Depth", "\(metadata.bitsPerComponent) bits/channel")
            infoRow("Transparency", metadata.hasAlpha ? "Yes" : "No")
            if metadata.frameCount > 1 {
              infoRow(asset.isPDF ? "Pages" : "Frames", String(metadata.frameCount))
            }
            if asset.modified != .distantPast {
              infoRow("Modified", asset.modified.formatted(date: .abbreviated, time: .shortened))
            }
          }
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            Text("LOCATION").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(
              .secondary)
            Text(asset.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button("Reveal in Finder", systemImage: "arrow.up.forward.app") { model.reveal() }.font(
              .caption)
          }
          if !model.edits.isIdentity {
            VStack(alignment: .leading, spacing: 8) {
              Label("Unsaved adjustments", systemImage: "slider.horizontal.3").font(.callout)
              Text("Export to save this view as a new image.").font(.caption).foregroundStyle(
                .secondary)
              Button("Export…") { model.exportSheet = true }
            }
          }
          Divider()
          DisclosureGroup("All Metadata") {
            VStack(alignment: .leading, spacing: 14) {
              ForEach(metadata.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                  Text(row.key).font(.system(size: 10)).foregroundStyle(.secondary)
                  Text(row.value).font(.system(size: 11)).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
              }
            }.padding(.top, 12)
          }.font(.callout)
        }.padding(20)
      }
    } else {
      ContentUnavailableView(
        "Image Information", systemImage: "info.circle",
        description: Text("Open an image to inspect its dimensions, color profile, and metadata."))
    }
  }
  private func infoRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text(title).foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
    }.font(.system(size: 11))
  }
}
