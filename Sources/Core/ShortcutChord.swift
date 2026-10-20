import Foundation

struct ShortcutChord: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String
    // Carbon modifier masks; keep persisted shortcuts independent of AppKit.
    static let command: UInt32 = 256, shift: UInt32 = 512, option: UInt32 = 2048, control: UInt32 = 4096
    var isValid: Bool {
        keyCode < 128 && modifiers & ~(Self.command | Self.shift | Self.option | Self.control) == 0
            && modifiers & (Self.command | Self.option | Self.control) != 0
            && !key.isEmpty && key.count <= 12 && !key.contains(where: { $0.isNewline })
    }
    func matches(_ other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    var keycaps: [String] {
        [(Self.control,"⌃"),(Self.option,"⌥"),(Self.shift,"⇧"),(Self.command,"⌘")]
            .compactMap { modifiers & $0.0 != 0 ? $0.1 : nil } + [key]
    }
    static let standard = Self(keyCode: 42, modifiers: command, key: "\\")
    static let alternate = Self(keyCode: 49, modifiers: control | option, key: "Space")
}
