import Foundation
import Testing
@testable import TeroCore

@Test func youtubeLinksNormaliseToOneVideo() {
  let canonical = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
  for link in ["https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&t=42s", "youtu.be/dQw4w9WgXcQ?si=abc",
               "https://m.youtube.com/watch?v=dQw4w9WgXcQ", "https://www.youtube.com/shorts/dQw4w9WgXcQ",
               "  https://music.youtube.com/watch?v=dQw4w9WgXcQ  "] {
    #expect(VideoLink.youtube(link) == canonical, "\(link)")
  }
  for text in ["https://vimeo.com/123", "https://www.youtube.com/playlist?list=PL123", "watch this https://youtu.be/dQw4w9WgXcQ",
               "https://www.youtube.com/watch?v=short", "https://evil.example/youtube.com/watch?v=dQw4w9WgXcQ", "Hello"] {
    #expect(VideoLink.youtube(text) == nil, "\(text)")
  }
}

@Test func downloadArgumentsKeepTheURLOutOfOptions() {
  let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
  let folder = URL(fileURLWithPath: "/tmp/Music")
  let mp3 = VideoDownloadCommand.arguments(url: url, format: .mp3, folder: folder, ffmpegFolder: URL(fileURLWithPath: "/opt/homebrew/bin"))
  #expect(mp3.suffix(2) == ["--", url.absoluteString])
  #expect(mp3.contains("--no-playlist") && mp3.contains("--no-overwrites"))
  #expect(mp3.contains("320K") && mp3.contains("mp3") && mp3.contains("/opt/homebrew/bin"))
  let mp4 = VideoDownloadCommand.arguments(url: url, format: .mp4, folder: folder, ffmpegFolder: nil)
  #expect(mp4.contains("--merge-output-format") && !mp4.contains("--extract-audio") && !mp4.contains("--ffmpeg-location"))
  #expect(mp4[mp4.firstIndex(of: "--paths")! + 1] == "/tmp/Music")
}

@Test func downloadProgressLinesParse() {
  #expect(VideoDownloadCommand.progress("[tero-progress]  42.5%") == 0.425)
  #expect(VideoDownloadCommand.progress("[tero-progress] 100.0%") == 1)
  #expect(VideoDownloadCommand.progress("/Users/me/Music/song.mp3") == nil)
}

@Test func downloadVideoIsOfferedFirstForYouTubeLinks() {
  let readout = SelectionReadout(applicationName: "Safari", processIdentifier: 0, status: .selected("https://youtu.be/dQw4w9WgXcQ"))
  let ranked = RecommendationEngine.rank(context: .init(selection: readout, applicationID: "com.apple.Safari"))
  #expect(ranked.first?.target == .native(.downloadVideo))
  let plain = SelectionReadout(applicationName: "Notes", processIdentifier: 0, status: .selected("Meet at noon"))
  #expect(!RecommendationEngine.rank(context: .init(selection: plain, applicationID: nil)).contains { $0.target == .native(.downloadVideo) })
  #expect(Action.downloadVideo.definition?.usesAI == false && Action.downloadVideo.definition?.rankedOnServer == false)
}
