import GlintCore
import SwiftUI

enum CanvasBackground: String, CaseIterable, Identifiable {
  case charcoal, black, white, checkerboard
  var id: Self { self }
  var title: String { rawValue.capitalized }
}

@MainActor @Observable
final class Preferences {
  @ObservationIgnored private let defaults: UserDefaults
  var wraps: Bool { didSet { save(wraps, "wraps") } }
  var remembersZoom: Bool { didSet { save(remembersZoom, "remembersZoom") } }
  var enlargesSmallImages: Bool { didSet { save(enlargesSmallImages, "enlargesSmallImages") } }
  var animatesImages: Bool { didSet { save(animatesImages, "animatesImages") } }
  var scrollToBrowse: Bool { didSet { save(scrollToBrowse, "scrollToBrowse") } }
  var nearestNeighbor: Bool { didSet { save(nearestNeighbor, "nearestNeighbor") } }
  var slideshowDelay: Double { didSet { save(slideshowDelay, "slideshowDelay") } }
  var randomSlideshow: Bool { didSet { save(randomSlideshow, "randomSlideshow") } }
  var background: CanvasBackground { didSet { save(background.rawValue, "background") } }

  init(defaults d: UserDefaults = .standard) {
    defaults = d
    d.register(defaults: [
      "wraps": true, "remembersZoom": true, "enlargesSmallImages": true,
      "animatesImages": true, "slideshowDelay": 5.0,
    ])
    wraps = d.bool(forKey: "wraps")
    remembersZoom = d.bool(forKey: "remembersZoom")
    enlargesSmallImages = d.bool(forKey: "enlargesSmallImages")
    animatesImages = d.bool(forKey: "animatesImages")
    scrollToBrowse = d.bool(forKey: "scrollToBrowse")
    nearestNeighbor = d.bool(forKey: "nearestNeighbor")
    slideshowDelay = max(0.5, d.double(forKey: "slideshowDelay"))
    randomSlideshow = d.bool(forKey: "randomSlideshow")
    background = CanvasBackground(rawValue: d.string(forKey: "background") ?? "") ?? .charcoal
  }
  private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}

struct PreferencesView: View {
  @Bindable var preferences: Preferences
  var body: some View {
    Form {
      Section("Browsing") {
        Toggle("Loop at the first and last image", isOn: $preferences.wraps)
        Toggle("Keep zoom when changing images", isOn: $preferences.remembersZoom)
        Toggle(
          "Use the scroll wheel to browse when the image fits", isOn: $preferences.scrollToBrowse)
        Toggle("Play animated images automatically", isOn: $preferences.animatesImages)
      }
      Section("Canvas") {
        Picker("Background", selection: $preferences.background) {
          ForEach(CanvasBackground.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Enlarge small images to fit", isOn: $preferences.enlargesSmallImages)
        Toggle("Show sharp pixels when zoomed in", isOn: $preferences.nearestNeighbor)
      }
      Section("Slideshow") {
        HStack {
          Text("Time per image")
          Slider(value: $preferences.slideshowDelay, in: 0.5...30, step: 0.5)
          Text("\(preferences.slideshowDelay, specifier: "%.1f") s").monospacedDigit().frame(
            width: 48)
        }
        Toggle("Random order", isOn: $preferences.randomSlideshow)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 450)
  }
}
