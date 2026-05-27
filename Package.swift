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
        .library(name: "SpeechTapInfrastructure", targets: ["SpeechTapInfrastructure"])
    ],
    targets: [
        // domain: 純粋ロジック。Foundation 以外・OS API・UI に依存しない。
        .target(
            name: "SpeechTapDomain"
        ),
        // infrastructure: OS API への接触のみ。domain の port を実装する。
        .target(
            name: "SpeechTapInfrastructure",
            dependencies: ["SpeechTapDomain"]
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
