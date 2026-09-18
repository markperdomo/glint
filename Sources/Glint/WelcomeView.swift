import SwiftUI

struct WelcomeView: View {
  let model: ViewerModel
  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          ZStack {
            RoundedRectangle(cornerRadius: 23).fill(Color(red: 0.89, green: 0.91, blue: 0.83))
              .frame(width: 88, height: 88)
            Image(systemName: "viewfinder").font(.system(size: 43, weight: .ultraLight))
              .foregroundStyle(Color(red: 0.29, green: 0.37, blue: 0.20))
            Image(systemName: "sparkle").font(.system(size: 21, weight: .light)).foregroundStyle(
              Color(red: 0.29, green: 0.37, blue: 0.20))
          }
          .padding(.bottom, 22)
          Text("Glint").font(.system(size: 36, weight: .medium))
          Button {
            model.openPanel()
          } label: {
            Label("Open Images or a Folder", systemImage: "folder").padding(.horizontal, 8).padding(
              .vertical, 4)
          }
          .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 30)
          Text("or drop them anywhere").font(.caption).foregroundStyle(.tertiary).padding(.top, 12)

          if !model.recentURLs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("Recent").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clearRecent() }.font(.caption).buttonStyle(.plain)
                  .foregroundStyle(.tertiary)
              }
              ForEach(Array(model.recentURLs.prefix(4)), id: \.self) { url in
                Button {
                  model.open([url])
                } label: {
                  HStack(spacing: 12) {
                    Image(systemName: "folder").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(url.lastPathComponent).font(.callout).lineLimit(1)
                      Text(
                        url.deletingLastPathComponent().path.replacingOccurrences(
                          of: NSHomeDirectory(), with: "~")
                      )
                      .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(
                        .middle)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                  }.padding(10).contentShape(Rectangle())
                }.buttonStyle(.plain)
              }
            }.frame(maxWidth: 390).padding(.top, 42)
          }
          HStack(spacing: 24) {
            keyHint("← →", "Browse")
            keyHint("F", "Fit")
            keyHint("1", "Actual pixels")
            keyHint("⌘ I", "Inspect")
          }.padding(.top, 44)
        }
        .frame(maxWidth: .infinity, minHeight: max(400, geometry.size.height - 48))
        .padding(.vertical, 24)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }
  private func keyHint(_ key: String, _ title: String) -> some View {
    VStack(spacing: 7) {
      Text(key).font(.system(size: 11, design: .monospaced)).padding(.horizontal, 8).padding(
        .vertical, 5
      )
      .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 5))
      Text(title).font(.system(size: 10)).foregroundStyle(.tertiary)
    }
  }
}
