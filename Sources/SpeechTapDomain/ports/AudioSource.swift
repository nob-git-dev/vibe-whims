import Foundation

/// 対象アプリの音声を PCM フレームのストリームとして供給する境界（実装は infrastructure）。
/// 本質【最重要】: 対象アプリ音声のみを供給し、他アプリ・マイク・システム音を混入させない。
public protocol AudioSource: Sendable {
    func start(app: AppId) async throws -> AsyncStream<AudioFrame>
    func stop() async
}
