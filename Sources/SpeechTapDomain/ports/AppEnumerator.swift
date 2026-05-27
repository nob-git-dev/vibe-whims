import Foundation

/// 音声を出力し得る／起動中アプリを列挙する境界（実装は infrastructure）。
public protocol AppEnumerator: Sendable {
    func listAudioCapableApps() async throws -> [TargetApp]
}
