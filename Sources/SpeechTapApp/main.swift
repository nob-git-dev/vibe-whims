import AppKit
import SpeechTapDomain
import SpeechTapInfrastructure

// Composition Root（ADR-2）。
// presentation 層 = OS/UI（AppKit）に依存してよい層。ここで infrastructure の具体 Adapter を
// 生成し、domain の TranscriptionService に port として注入する。domain は具体型を一切知らない。
//
// メニューバー常駐（LSUIElement + accessory policy で Dock 非表示）。
// 最小 UI: 対象アプリ選択 / 開始・停止 / 文字起こし表示 / 権限案内。

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Dock 非表示・メニューバー常駐
let delegate = AppDelegate()
app.delegate = delegate
app.run()
