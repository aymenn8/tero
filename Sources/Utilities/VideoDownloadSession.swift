import AppKit
import Observation

/// Download one YouTube video with the person's installed yt-dlp: choose MP4 or MP3, then a folder.
/// Nothing is fetched until both choices are made; cancelling stops the process.
@MainActor @Observable
final class VideoDownloadSession {
  enum Stage: Equatable { case format, folder, downloading, finished }
  let url: URL
  private(set) var stage: Stage = .format
  private(set) var format: VideoFormat = .mp4
  private(set) var progress: Double = 0
  private(set) var message: String?
  private(set) var output: URL?
  var selectedID: String? = VideoFormat.mp4.rawValue
  @ObservationIgnored private var process: Process?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private let back: () -> Void
  @ObservationIgnored private let changed: () -> Void
  private static let recentKey = "tero.recentDownloadFolders"
  static let installCommand = "brew install yt-dlp ffmpeg"

  init(url: URL, back: @escaping () -> Void, changed: @escaping () -> Void) {
    self.url = url; self.back = back; self.changed = changed
  }

  var toolMissing: Bool { VideoDownloadCommand.locate("yt-dlp") == nil }
  var succeeded: Bool { stage == .finished && output != nil }
  var busy: Bool { stage == .downloading }

  var hint: String {
    if toolMissing { return "Downloads use yt-dlp. Install it with Homebrew: \(Self.installCommand)" }
    switch stage {
    case .format: return "Only download videos you own or have permission to save."
    case .folder: return format.detail + " · choose where to save it"
    case .downloading: return progress > 0 ? "Downloading · \(Int(progress * 100))%" : "Starting download…"
    case .finished: return output.map { "Saved to " + $0.deletingLastPathComponent().lastPathComponent } ?? ""
    }
  }

  private var folders: [URL] {
    let recent = (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).map { URL(fileURLWithPath: $0) }
    return Array((recent + [format.defaultFolder, FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")])
      .reduce(into: [URL]()) { list, folder in
        if !list.contains(where: { $0.standardizedFileURL == folder.standardizedFileURL }),
           (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { list.append(folder) }
      }.prefix(2))
  }

  var presentation: ModeChoicePresentation {
    let options: [ModeChoice]
    if toolMissing {
      options = [.init(id: "copy-install", title: "Copy install command", label: "Copy the Homebrew command that installs yt-dlp", iconName: "doc.on.doc")]
    } else {
      switch stage {
      case .format:
        options = VideoFormat.allCases.map { .init(id: $0.rawValue, title: $0.title, label: $0.detail, iconName: $0 == .mp4 ? "film" : "music.note", help: $0.detail) }
      case .finished:
        options = [.init(id: "reveal", title: "Show in Finder", label: "Show the downloaded file in Finder", iconName: "folder")]
      case .folder, .downloading:
        options = folders.enumerated().map { index, folder in
          .init(id: "folder-\(index)", title: folder.lastPathComponent, label: "Save to \(folder.path)", iconName: "folder")
        } + [.init(id: "browse", title: "Choose folder…", label: "Choose where to save")]
      }
    }
    return .init(step: .init(label: "Download video", choices: options, selectedID: selectedID ?? options.first?.id,
                             backLabel: stage == .folder ? "Back to formats" : "Back to actions"),
      activityTitle: busy ? "Downloading" : nil,
      select: { [weak self] in self?.selectedID = $0 },
      perform: { [weak self] id in self?.choose(id) })
  }

  private func choose(_ id: String?) {
    guard let id else {
      if stage == .folder { stage = .format; selectedID = format.rawValue; message = nil; changed() } else { back() }
      return
    }
    if id == "reveal" { revealInFinder(); back(); return }
    if id == "copy-install" {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(Self.installCommand, forType: .string)
      message = "Copied. Paste it in Terminal, then try again."
      changed(); return
    }
    if stage == .format, let value = VideoFormat(rawValue: id) {
      format = value; stage = .folder; selectedID = "folder-0"; message = nil; changed(); return
    }
    guard stage == .folder else { return }
    if id == "browse" {
      let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
      picker.allowsMultipleSelection = false; picker.canCreateDirectories = true; picker.prompt = "Save Here"
      if picker.runModal() == .OK, let folder = picker.url { start(in: folder) }
      return
    }
    if id.hasPrefix("folder-"), let index = Int(id.dropFirst(7)), folders.indices.contains(index) { start(in: folders[index]) }
  }

  private func start(in folder: URL) {
    guard let tool = VideoDownloadCommand.locate("yt-dlp") else { changed(); return }
    let ffmpeg = VideoDownloadCommand.locate("ffmpeg")
    if format == .mp3 && ffmpeg == nil { message = "MP3 needs ffmpeg: brew install ffmpeg"; changed(); return }
    let recent = [folder.path] + (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).filter { $0 != folder.path }
    UserDefaults.standard.set(Array(recent.prefix(5)), forKey: Self.recentKey)
    stage = .downloading; progress = 0; message = nil; changed()
    let process = Process()
    process.executableURL = tool
    process.arguments = VideoDownloadCommand.arguments(url: url, format: format, folder: folder, ffmpegFolder: ffmpeg?.deletingLastPathComponent())
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    self.process = process
    work = Task { [weak self] in
      do {
        try process.run()
        var saved: URL?
        for try await line in output.fileHandleForReading.bytes.lines {
          guard let self, !Task.isCancelled else { break }
          if let value = VideoDownloadCommand.progress(line) {
            if value - progress >= 0.01 || value == 1 { progress = value; changed() }
          } else if line.hasPrefix("/"), FileManager.default.fileExists(atPath: line) {
            saved = URL(fileURLWithPath: line)
          }
        }
        process.waitUntilExit()
        guard let self, !Task.isCancelled else { return }
        self.process = nil
        if process.terminationStatus == 0, let saved {
          self.output = saved; stage = .finished; selectedID = "reveal"
        } else {
          stage = .folder
          message = "Couldn’t download this video. It may be private, age-restricted or unavailable, or yt-dlp needs an update: brew upgrade yt-dlp"
        }
        changed()
      } catch {
        guard let self, !Task.isCancelled else { return }
        stage = .folder; message = "Couldn’t start yt-dlp."; changed()
      }
    }
  }

  func revealInFinder() {
    if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
  }

  func cancel() {
    work?.cancel()
    if let process, process.isRunning { process.terminate() }
    process = nil
  }
}
