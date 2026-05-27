import Foundation
import Synchronization
import SpeechTapDomain
#if canImport(CoreAudio)
import CoreAudio
import AudioToolbox
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(os)
import os
#endif

/// AudioSource 実装: Core Audio Process Tap（ADR-1）。
/// PID → AudioObjectID（kAudioHardwarePropertyTranslatePIDToProcessObject）→ CATapDescription（対象プロセス限定）
/// → Aggregate Device を構成し、対象アプリ出力のみをタップする。
/// OS 型 ⇔ domain 値型（AudioFrame）の変換境界をここに置く。
///
/// 【最重要本質】対象アプリ音声のみを供給し、他アプリ・マイク・システム音を混入させないこと。
/// → `CATapDescription(stereoMixdownOfProcesses:)` で対象プロセスのみを含むタップを作る
///   （グローバルタップ・除外タップは使わない）ことで構造的に非混入を担保する設計。
///
/// 設計（リアルタイム制約）:
/// - I/O コールバック（リアルタイムスレッド）はサンプルをコピーして AsyncStream に yield するだけ。
///   重い処理・確保・ブロッキングを行わない。フォーマット変換は下流（SpeechAnalyzerAdapter）で行う。
///
/// 実機検証項目（SPEC 手動検証項目・ユニットテスト不能）:
/// - 権限ダイアログが出るか / 未許可検出（タップ生成の戻り値で検出）。
/// - 【最重要】対象アプリの音声のみ取れるか（非混入）。複数プロセスアプリの挙動。
/// - native format の実値。リアルタイムスレッドでのドロップアウト有無。
public final class ProcessTapAudioSource: AudioSource, @unchecked Sendable {
    public init() {}

    #if canImport(CoreAudio)
    // タップ／集約デバイスのライフサイクル状態（stop で解放）。
    private final class TapState {
        var processTapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        var ioProcID: AudioDeviceIOProcID?
        var continuation: AsyncStream<AudioFrame>.Continuation?
        var format: AudioStreamFormat = AudioStreamFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: false)

        /// 観測（リアルタイムスレッド安全）: IOProc 呼び出し回数と yield 済みフレーム数。
        /// IOProc 内では atomic インクリメントのみ行い、Logger 呼び出しは最初の数回に間引く。
        /// stop 時にサマリを出力して「IOProc が呼ばれたか / 何フレーム流したか」を判定可能にする。
        let ioProcCallCount = Atomic<Int>(0)
        let yieldedFrameCount = Atomic<Int>(0)
    }
    #endif

    #if canImport(os)
    private let tapLog = AppLog.logger(.tap)
    private let ioLog = AppLog.logger(.ioproc)
    #endif

    #if canImport(CoreAudio)
    private let lock = NSLock()
    private var state: TapState?

    private func setState(_ value: TapState?) {
        lock.lock(); defer { lock.unlock() }
        state = value
    }

    private func takeState() -> TapState? {
        lock.lock(); defer { lock.unlock() }
        let s = state
        state = nil
        return s
    }
    #endif

    public func start(app: AppId) async throws -> AsyncStream<AudioFrame> {
        #if canImport(CoreAudio)
        // 1. PID 解決。AppId.rawValue が "pid:<n>" なら直接 PID、bundleId なら NSWorkspace で解決する。
        guard let pid = try resolvePID(for: app) else {
            #if canImport(os)
            tapLog.error("PID resolution failed for app=\(app.rawValue, privacy: .public)")
            #endif
            throw NotImplemented.processTap
        }
        #if canImport(os)
        tapLog.info("start: app=\(app.rawValue, privacy: .public) resolved pid=\(pid)")
        #endif

        // 2. PID → AudioObjectID（オーディオプロセスオブジェクト）。
        let processObjectID = try translatePIDToAudioObject(pid)
        #if canImport(os)
        tapLog.info("translated pid=\(pid) -> processObjectID=\(processObjectID)")
        #endif

        // 3. CATapDescription（対象プロセスのみ＝非混入）。出力を素通しのままタップ（unmuted）。
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = CATapMuteBehavior.unmuted

        // 4. プロセスタップ生成。未許可・失敗は戻り値で検出する（私的 TCC API に依存しない）。
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let createStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard createStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioTapError.tapCreationFailed(createStatus)
        }

        #if canImport(os)
        tapLog.info("tap created tapID=\(tapID)")
        #endif

        // 5. タップの native format を取得（kAudioTapPropertyFormat → ASBD → AudioStreamFormat）。
        let asbd = try tapStreamDescription(tapID)
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let format = AudioStreamFormat(
            sampleRate: asbd.mSampleRate,
            channelCount: Int(asbd.mChannelsPerFrame),
            isInterleaved: !isNonInterleaved
        )
        #if canImport(os)
        // 仮説 B 判定の核心: タップ native ASBD の全フィールドを記録する。
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        tapLog.info(
            """
            tap native ASBD: sampleRate=\(asbd.mSampleRate) \
            channelsPerFrame=\(asbd.mChannelsPerFrame) \
            formatFlags=0x\(String(asbd.mFormatFlags, radix: 16), privacy: .public) \
            isFloat=\(isFloat) isNonInterleaved=\(isNonInterleaved) \
            bitsPerChannel=\(asbd.mBitsPerChannel) \
            bytesPerFrame=\(asbd.mBytesPerFrame) \
            bytesPerPacket=\(asbd.mBytesPerPacket) \
            framesPerPacket=\(asbd.mFramesPerPacket) \
            formatID=\(asbd.mFormatID)
            """
        )
        #endif

        // 6. タップを含む Aggregate Device を構成し、IOProc で PCM を受け取る。
        let aggregateID = try createAggregateDevice(tapUUID: tapDescription.uuid)
        #if canImport(os)
        tapLog.info("aggregate device created aggregateID=\(aggregateID)")
        #endif

        let (stream, continuation) = AsyncStream.makeStream(of: AudioFrame.self)

        let tapState = TapState()
        tapState.processTapID = tapID
        tapState.aggregateDeviceID = aggregateID
        tapState.continuation = continuation
        tapState.format = format

        // 7. IOProc 登録。リアルタイムスレッドではサンプルをコピーして yield するだけ。
        let ioProcID = try registerIOProc(aggregateID: aggregateID, state: tapState)
        tapState.ioProcID = ioProcID

        setState(tapState)

        // 8. デバイス開始。
        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        #if canImport(os)
        tapLog.info("AudioDeviceStart status=\(startStatus) (noErr=\(startStatus == noErr))")
        #endif
        guard startStatus == noErr else {
            await stop()
            throw AudioTapError.deviceStartFailed(startStatus)
        }

        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        return stream
        #else
        throw NotImplemented.processTap
        #endif
    }

    public func stop() async {
        #if canImport(CoreAudio)
        guard let s = takeState() else { return }
        #if canImport(os)
        // 観測サマリ: IOProc が何回呼ばれ、何フレーム yield したか。
        // ここが 0 なら仮説 A（タップが無音 / IOProc 未呼び出し）が濃厚。
        tapLog.info(
            "stop summary: ioProcCalls=\(s.ioProcCallCount.load(ordering: .relaxed)) yieldedFrames=\(s.yieldedFrameCount.load(ordering: .relaxed))"
        )
        #endif
        if let ioProcID = s.ioProcID, s.aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(s.aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(s.aggregateDeviceID, ioProcID)
        }
        if s.aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(s.aggregateDeviceID)
        }
        if s.processTapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(s.processTapID)
        }
        s.continuation?.finish()
        #endif
    }

    #if canImport(CoreAudio)
    // MARK: - PID 解決

    private func resolvePID(for app: AppId) throws -> pid_t? {
        let raw = app.rawValue
        if raw.hasPrefix("pid:"), let n = Int32(raw.dropFirst(4)) {
            return n
        }
        #if canImport(AVFoundation)
        // bundleId として NSWorkspace から PID を解決する（RunningAppProvider と同じ識別子規約）。
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: raw) {
            return running.processIdentifier
        }
        #endif
        return nil
    }

    // MARK: - Core Audio property helpers

    private func translatePIDToAudioObject(_ pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputPID = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &inputPID) { pidPtr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPtr,
                &size,
                &objectID
            )
        }
        guard status == noErr, objectID != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioTapError.pidTranslationFailed(status)
        }
        return objectID
    }

    private func tapStreamDescription(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { throw AudioTapError.tapFormatFailed(status) }
        return asbd
    }

    private func createAggregateDevice(tapUUID: UUID) throws -> AudioObjectID {
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SpeechTap-Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            // private にすると他アプリ・システムに見えない（常駐アプリとして無害）。
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // 対象プロセス限定タップのみを sub-tap として持つ（= 非混入）。
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString]
            ]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioTapError.aggregateCreationFailed(status)
        }
        return aggregateID
    }

    private func registerIOProc(aggregateID: AudioObjectID, state: TapState) throws -> AudioDeviceIOProcID {
        // Unmanaged で TapState をコールバックへ渡す（リアルタイムスレッドで参照する）。
        let context = Unmanaged.passUnretained(state).toOpaque()
        #if canImport(os)
        // Logger は Sendable な値型。self を捕捉せず値コピーで渡す（リアルタイム安全）。
        let ioLog = self.ioLog
        #endif
        var ioProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, inInputData, _, _, _ in
            // リアルタイムスレッド: コピーして yield するだけ。確保・ロック・ブロッキングをしない。
            let st = Unmanaged<TapState>.fromOpaque(context).takeUnretainedValue()

            // 観測（リアルタイム安全）: 呼び出し回数を atomic に加算する。
            // Logger 呼び出しは最初の数回だけに間引く（リアルタイムスレッドで重い処理を避ける）。
            let callIndex = st.ioProcCallCount.add(1, ordering: .relaxed).newValue
            let ablPointer = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))

            #if canImport(os)
            if callIndex <= 3 {
                // 仮説 A/B 判定の核心: バッファ構成（mNumberBuffers / 各チャンネル数・バイト数）を記録。
                let numBuffers = ablPointer.count
                let firstChannels = ablPointer.first?.mNumberChannels ?? 0
                let firstBytes = ablPointer.first?.mDataByteSize ?? 0
                let firstFloatCount = Int(firstBytes) / MemoryLayout<Float>.size
                ioLog.info(
                    """
                    IOProc call #\(callIndex): mNumberBuffers=\(numBuffers) \
                    first.mNumberChannels=\(firstChannels) \
                    first.mDataByteSize=\(firstBytes) \
                    computedFloatCount(first buffer)=\(firstFloatCount) \
                    declaredFormat.channels=\(st.format.channelCount) \
                    declaredFormat.interleaved=\(st.format.isInterleaved)
                    """
                )
            }
            #endif

            guard let continuation = st.continuation else { return }
            guard let firstBuffer = ablPointer.first, let mData = firstBuffer.mData else { return }
            let floatCount = Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard floatCount > 0 else { return }
            let floatPointer = mData.assumingMemoryBound(to: Float.self)
            let samples = Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
            let frame = AudioFrame(
                samples: samples,
                format: st.format,
                timestamp: Date().timeIntervalSinceReferenceDate
            )
            continuation.yield(frame)
            st.yieldedFrameCount.add(1, ordering: .relaxed)
        }
        guard status == noErr, let ioProcID else {
            throw AudioTapError.ioProcCreationFailed(status)
        }
        return ioProcID
    }
    #endif
}

#if canImport(CoreAudio)
/// Process Tap 構成・起動で失敗した OS レベルのエラー（OSStatus を保持）。
enum AudioTapError: Error {
    case pidTranslationFailed(OSStatus)
    case tapCreationFailed(OSStatus)
    case tapFormatFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
}
#endif
