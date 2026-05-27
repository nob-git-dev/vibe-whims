import Testing
import Foundation

/// アーキテクチャ固定要件のガードテスト。
/// 固定要件: domain は OS API / UI フレームワークを import しない（AppKit/CoreAudio/Speech/ScreenCaptureKit 等）。
/// SPM は別ターゲット（infrastructure/presentation）の import を循環依存としてコンパイル時に弾くが、
/// CoreAudio 等のシステムフレームワークは import 可能なため、ソース走査で構造的に禁止する。
struct ArchitectureGuardTests {

    /// domain ターゲットのソースに OS/UI フレームワーク import が無いことを保証する。
    @Test("domain ソースは OS API / UI フレームワークを import していない（OS 非依存の構造的担保）")
    func domainHasNoOSImports() throws {
        let forbidden = [
            "import AppKit",
            "import UIKit",
            "import SwiftUI",
            "import CoreAudio",
            "import AudioToolbox",
            "import AVFoundation",
            "import AVFAudio",
            "import Speech",
            "import ScreenCaptureKit",
            "import CoreMedia"
        ]

        let domainDir = try domainSourceDirectory()
        let files = try swiftFiles(in: domainDir)
        #expect(!files.isEmpty, "domain ソースが見つからない: \(domainDir.path)")

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for line in contents.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                for bad in forbidden where trimmed == bad || trimmed.hasPrefix(bad + " ") {
                    Issue.record("禁止 import を検出: \(file.lastPathComponent) に '\(bad)'（domain は OS/UI 非依存）")
                }
            }
        }
    }

    // このテストファイル(.../Tests/SpeechTapDomainTests/X.swift)から
    // パッケージルートを辿り Sources/SpeechTapDomain を特定する。
    private func domainSourceDirectory() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../speech-tap/Tests/SpeechTapDomainTests/ArchitectureGuardTests.swift
        let packageRoot = thisFile
            .deletingLastPathComponent() // SpeechTapDomainTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SpeechTapDomain")
    }

    private func swiftFiles(in dir: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }
}
