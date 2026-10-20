import Foundation

/// A single YouTube video link, normalised to its canonical watch URL.
/// Playlist, timestamp and tracking parameters are dropped so only that one video downloads.
enum VideoLink {
  static func youtube(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count <= 2048, !trimmed.contains(where: \.isWhitespace),
          let components = URLComponents(string: trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed),
          ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
          let host = components.host?.lowercased() else { return nil }
    let path = components.path.split(separator: "/").map(String.init)
    let id: String?
    switch host {
    case "youtu.be", "www.youtu.be":
      id = path.first
    case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
      if path.first == "watch" { id = components.queryItems?.first { $0.name == "v" }?.value }
      else if path.count == 2, ["shorts", "live", "embed"].contains(path[0]) { id = path[1] }
      else { id = nil }
    default: id = nil
    }
    guard let id, id.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil else { return nil }
    return URL(string: "https://www.youtube.com/watch?v=" + id)
  }
}

enum VideoFormat: String, CaseIterable, Sendable {
  case mp4, mp3
  var title: String { rawValue.uppercased() }
  var detail: String { self == .mp4 ? "Video, best available quality" : "Audio only, 320 kbps" }
  var defaultFolder: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: self == .mp4 ? "Movies" : "Music")
  }
}

/// yt-dlp arguments and progress parsing. No shell: arguments are passed directly to the process.
enum VideoDownloadCommand {
  static let progressPrefix = "[tero-progress]"

  static func arguments(url: URL, format: VideoFormat, folder: URL, ffmpegFolder: URL?) -> [String] {
    var arguments = ["--no-playlist", "--no-overwrites", "--newline", "--no-warnings", "--no-simulate",
                     "--progress-template", "download:\(progressPrefix) %(progress._percent_str)s",
                     "--print", "after_move:filepath",
                     "--paths", folder.path, "--output", "%(title).150B [%(id)s].%(ext)s"]
    if let ffmpegFolder { arguments += ["--ffmpeg-location", ffmpegFolder.path] }
    switch format {
    case .mp4: arguments += ["--format", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b", "--merge-output-format", "mp4"]
    case .mp3: arguments += ["--extract-audio", "--audio-format", "mp3", "--audio-quality", "320K"]
    }
    // "--" ends options, so the URL can never be read as one.
    return arguments + ["--", url.absoluteString]
  }

  /// Download percentage (0...1) from a progress line, or nil for any other output.
  static func progress(_ line: String) -> Double? {
    guard line.hasPrefix(progressPrefix) else { return nil }
    let value = line.dropFirst(progressPrefix.count).trimmingCharacters(in: .whitespaces).replacing("%", with: "")
    return Double(value).map { min(1, max(0, $0 / 100)) }
  }

  /// Standard install locations, so the app never runs a shell to find tools.
  static func locate(_ tool: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
    ["/opt/homebrew/bin", "/usr/local/bin", home.appending(path: ".local/bin").path, "/usr/bin"]
      .map { URL(fileURLWithPath: $0).appending(path: tool) }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}
