import Foundation

/// Directory notifications catch additions/removals; a file watch catches
/// in-place edits. Recursive subtree changes are picked up by manual refresh.
@MainActor
final class FolderMonitor {
  private var sources: [any DispatchSourceFileSystemObject] = []
  private var debounce: Task<Void, Never>?

  func watch(_ urls: [URL], onChange: @escaping @MainActor () -> Void) {
    stop()
    for url in Set(urls) {
      let fd = Darwin.open(url.path, O_EVTONLY)
      guard fd >= 0 else { continue }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .delete, .rename, .attrib, .extend], queue: .main)
      source.setCancelHandler { Darwin.close(fd) }
      source.setEventHandler { [weak self] in
        Task { @MainActor [weak self] in
          self?.debounce?.cancel()
          self?.debounce = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            onChange()
          }
        }
      }
      sources.append(source)
      source.resume()
    }
  }
  func stop() {
    debounce?.cancel()
    for source in sources { source.cancel() }
    sources.removeAll()
  }
}
