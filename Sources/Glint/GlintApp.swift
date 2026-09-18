import AppKit
import SwiftUI

@main
struct GlintApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var preferences: Preferences
  @State private var model: ViewerModel

  init() {
    let preferences = Preferences()
    _preferences = State(initialValue: preferences)
    _model = State(initialValue: ViewerModel(preferences: preferences))
  }

  var body: some Scene {
    Window("Glint", id: "viewer") {
      ContentView(model: model)
        .onAppear { delegate.connect(model) }
    }
    .defaultSize(width: 1180, height: 780)
    .windowResizability(.contentMinSize)
    .commands { ViewerCommands(model: model) }

    Settings { PreferencesView(preferences: preferences) }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private weak var model: ViewerModel?
  private var pending: [URL] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    let paths = CommandLine.arguments.dropFirst().filter {
      !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
    }
    if !paths.isEmpty {
      let urls = paths.map { URL(fileURLWithPath: $0) }
      if let model { model.open(urls) } else { pending = urls }
    }
    NSApp.activate(ignoringOtherApps: true)
  }
  func connect(_ model: ViewerModel) {
    self.model = model
    if !pending.isEmpty {
      model.open(pending)
      pending = []
    }
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    if let model {
      model.bringToFront?()
      model.open(urls)
      model.window?.makeKeyAndOrderFront(nil)
    } else {
      pending = urls
    }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    model?.bringToFront?()
    model?.window?.makeKeyAndOrderFront(nil)
    return true
  }
  func applicationWillTerminate(_ notification: Notification) { model?.suspend() }
}
