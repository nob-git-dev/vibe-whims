import Foundation

/// 設定値の供給境界（実装は infrastructure: config.yaml / .env 読み込み）。
/// 本質: 対象アプリ識別子・認識言語・出力先をコード直書きせず外部化する。
public protocol Config: Sendable {
    var targetAppId: AppId? { get }
    var locale: Locale { get }
    var outputPath: String { get }
}
