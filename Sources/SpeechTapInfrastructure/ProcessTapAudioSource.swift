import Foundation
import SpeechTapDomain
#if canImport(CoreAudio)
import CoreAudio
#endif

/// AudioSource 実装: Core Audio Process Tap（ADR-1）。
/// PID → AudioObjectID（kAudioHardwarePropertyTranslatePIDToProcessObject）→ CATapDescription（対象プロセス限定）
/// → Aggregate Device を構成し、対象アプリ出力のみをタップする。
/// OS 型 ⇔ domain 値型（AudioFrame）の変換境界をここに置く。
///
/// 【最重要本質】対象アプリ音声のみを供給し、他アプリ・マイク・システム音を混入させないこと。
///
/// TODO（実機検証が必要なため未実装。SPEC「## テスト計画 / infrastructure 手動検証項目」参照）:
/// - PID → AudioObjectID 変換（kAudioHardwarePropertyTranslatePIDToProcessObject）
/// - CATapDescription（processes: [対象プロセス] に限定）で AudioHardwareCreateProcessTap
/// - Aggregate Device 構成・IOProc 登録
/// - I/O コールバックはロックフリーリングバッファに積むだけ（リアルタイムスレッドでブロッキング・確保禁止）
/// - native format（kAudioTapPropertyFormat の ASBD → AVAudioFormat）→ AudioStreamFormat へ正規化
/// - AVAudioPCMBuffer → AudioFrame.samples([Float]) へ変換し AsyncStream で yield
public final class ProcessTapAudioSource: AudioSource, @unchecked Sendable {
    public init() {}

    public func start(app: AppId) async throws -> AsyncStream<AudioFrame> {
        // TODO: Core Audio Process Tap を構成し、対象プロセスの PCM を AsyncStream で供給する。
        throw NotImplemented.processTap
    }

    public func stop() async {
        // TODO: IOProc 停止・Aggregate Device / Tap の破棄・リソース解放。
    }
}

enum NotImplemented: Error {
    case processTap
    case speechAnalyzer
}
