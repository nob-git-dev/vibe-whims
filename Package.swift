// swift-tools-version: 6.1
import PackageDescription

// 3層を物理的にモジュール分離する（固定要件 / ADR-2）。
// 依存方向: presentation → infrastructure → domain の一方向のみ。
// SpeechTapDomain は Foundation のみに依存し、他ターゲットを依存に持たないため、
// domain から presentation / infrastructure / OS フレームワークを import すると
// コンパイルエラーになる（逆依存をコンパイル時に不可能化）。
let package = Package(
    name: "speech-tap",
    platforms: [
        .macOS(.v15) // 実運用は macOS 26+ 前提（SpeechAnalyzer）。SPM の列挙上は v15 を下限にし、実コードで availability ガードする。
    ],
    products: [
        .library(name: "SpeechTapDomain", targets: ["SpeechTapDomain"]),
        .library(name: "SpeechTapInfrastructure", targets: ["SpeechTapInfrastructure"]),
        .executable(name: "SpeechTapApp", targets: ["SpeechTapApp"])
    ],
    targets: [
        // domain: 純粋ロジック。Foundation 以外・OS API・UI に依存しない。
        // C シム（CProcResponsibility）にも依存しない（OS/C 非依存を維持・ADR-8 / Should-1）。
        .target(
            name: "SpeechTapDomain"
        ),
        // C シム（infrastructure 専用）: libSystem の private シンボル
        // responsibility_get_pid_responsible_for_pid を Swift から安全に呼ぶための薄いラッパ。
        // domain はこれに依存しない（層分離を維持）。@_silgen_name を避け明示的 C ターゲットにする。
        .target(
            name: "CProcResponsibility"
        ),
        // infrastructure: OS API への接触のみ。domain の port を実装する。
        // responsiblePID 取得のため C シム CProcResponsibility にのみ依存（domain には入れない）。
        .target(
            name: "SpeechTapInfrastructure",
            dependencies: ["SpeechTapDomain", "CProcResponsibility"]
        ),
        // presentation + Composition Root（ADR-2）。
        // メニューバー常駐 UI を持ち、infrastructure の具体 Adapter を生成して domain に注入する。
        // OS/UI（AppKit）に依存してよい層。依存方向は外→内（presentation → infra → domain）のまま。
        .executableTarget(
            name: "SpeechTapApp",
            dependencies: ["SpeechTapDomain", "SpeechTapInfrastructure"],
            // Info.plist は -sectcreate でバイナリに埋め込むため、リソース複製対象から除外する
            // （unhandled 警告も消える）。config.default.conf はバンドルへ複製する。
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/config.default.conf")
            ],
            linkerSettings: [
                // NSAudioCaptureUsageDescription を含む Info.plist を実行ファイルに埋め込む
                // （TCC ダイアログを正しく出すため。Hardened Runtime / 署名は /deploy で詰める）。
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/SpeechTapApp/Resources/Info.plist"
                ])
            ]
        ),
        // domain のユニットテスト。fake/stub port を注入して OS なしで検証する。
        .testTarget(
            name: "SpeechTapDomainTests",
            dependencies: ["SpeechTapDomain"]
        ),
        // infrastructure の OS 非依存部（ConfigLoader 等）のユニットテスト。
        .testTarget(
            name: "SpeechTapInfrastructureTests",
            dependencies: ["SpeechTapInfrastructure", "SpeechTapDomain"]
        )
    ]
)
