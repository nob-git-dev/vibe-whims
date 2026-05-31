# vibe-whims

🌐 **English** | [日本語](#日本語)

> A small collection of **AI-native software experiments** — two independent projects, each living on its own branch.

| Project | Branch | What it is |
|---|---|---|
| 🎮 **NES Binary Experiment** | [`main`](https://github.com/nob-git-dev/vibe-whims/tree/main) (this branch) | Can an AI emit a working binary **without writing source code**, by authoring annotated hex directly? Produces a real `.nes` ROM, playable in a Rust→WASM browser emulator. |
| 🎙 **speech-tap** | [`speech-tap`](https://github.com/nob-git-dev/vibe-whims/tree/speech-tap) | A macOS menu-bar app that transcribes the audio of a **single chosen app** in real time, fully on-device, using Apple's new **SpeechAnalyzer** (macOS 26), **Core Audio Process Tap**, and the **Translation** framework. |

> The two projects share this repository only as a home for experiments — their code and git history are independent. Switch branches above to explore each. The rest of this page documents the **NES Binary Experiment** (this branch); see the [`speech-tap` branch README](https://github.com/nob-git-dev/vibe-whims/tree/speech-tap) for that project.

---

## 🎮 NES Binary Experiment

> **Can AI output binary directly — without writing source code?**

This project is an experiment to answer that question.

### The Idea

Source code exists because humans need to read it.
If an AI is the one generating and maintaining the program, human-readable source is just an intermediate step — a translation layer that nobody asked for.

**What if we remove it?**

Instead of the traditional flow:

```
AI writes source code → assembler/compiler → binary
```

This project tries:

```
AI writes annotated hex → hex-to-bytes converter → binary
```

No assembler. No compiler. No `.asm` files. The AI reads and writes bytes directly, expressed as annotated hex.

### How It Works

**The "Source": `game.rom.txt`** — The only source of truth is a plain-text annotated hex dump. The AI writes 6502 machine code as raw hex bytes, with comments as the only documentation. No mnemonics, no labels, no assembler directives.

**The Converter: `generate.py`** — A ~100-line Python script. It does exactly one thing: parse `game.rom.txt` and write `game.nes`. No translation. No compilation. Just `int(token, 16)` for each byte.

```bash
uv run generate.py
# → game.nes (24592 bytes, iNES format)
```

**The Output: `game.nes`** — A valid NES ROM that runs on any NES emulator.

### Play in the Browser

The companion emulator (Rust → WebAssembly) lets you run the generated ROM directly in the browser — closing the loop from "AI writes hex" to "game runs in browser."

**[▶ Play in Browser](https://nob-git-dev.github.io/vibe-whims/)**

Load any Mapper 0 (NROM) `.nes` file, including `game.nes` from this repo.

| Key | NES Button |
|-----|-----------|
| Arrow keys | D-Pad |
| Z | B |
| X | A |
| Shift | Select |
| Enter | Start |

### Repository Structure

```
game.rom.txt          ← The "source". AI reads and writes this.
game.nes              ← The output. Distribute this.
generate.py           ← The converter. hex → bytes, nothing more.
domain/               ← Python domain layer (parser, builder)
tests/                ← Unit tests for the converter
emulator/             ← Rust→WASM NES emulator (browser)
```

### Why NES?

- The 6502 instruction set is small (~150 instructions), making it feasible for an AI to reason about raw opcodes.
- The iNES format is well-documented and has a fixed, simple structure.
- Mapper 0 (NROM) requires no bank switching — what you write is what you get.
- Decades of emulators mean the output is immediately verifiable.

### Status

- [x] AI-written `game.rom.txt` → valid `.nes` ROM
- [x] Player sprite, enemy, collision detection, controller input
- [x] Browser-based emulator (Rust → WASM)
- [ ] More complex programs (scrolling, multiple enemies, score display)
- [ ] Experiment log: what breaks, what works, what surprises

*An experiment in AI-native binary generation. No source code required.*

---

## 日本語

🌐 [English](#vibe-whims) | **日本語**

> **AIネイティブなソフトウェア実験**の小さなコレクション。2つの独立したプロジェクトが、それぞれ別のブランチに存在します。

| プロジェクト | ブランチ | 概要 |
|---|---|---|
| 🎮 **NES バイナリ実験** | [`main`](https://github.com/nob-git-dev/vibe-whims/tree/main)（このブランチ） | AIは**ソースコードを書かずに**、アノテーション付きの hex を直接書くことで動くバイナリを生成できるか？ 実際の `.nes` ROM を生成し、Rust→WASM のブラウザエミュレータで実行できる。 |
| 🎙 **speech-tap** | [`speech-tap`](https://github.com/nob-git-dev/vibe-whims/tree/speech-tap) | **選んだ1つのアプリ**の音声だけを、完全オンデバイスでリアルタイム文字起こしする macOS メニューバーアプリ。Apple の新しい **SpeechAnalyzer**（macOS 26）・**Core Audio Process Tap**・**Translation** framework を使用。 |

> 2つのプロジェクトは、実験の置き場としてこのリポジトリを共有しているだけで、コードも git 履歴も独立しています。上のブランチを切り替えてそれぞれをご覧ください。このページの以降は **NES バイナリ実験**（このブランチ）の説明です。speech-tap は [`speech-tap` ブランチの README](https://github.com/nob-git-dev/vibe-whims/tree/speech-tap) を参照してください。

---

## 🎮 NES バイナリ実験

> **AIはソースコードを書かずに、バイナリを直接出力できるか？**

このプロジェクトは、その問いに答えるための実験です。

### アイデア

ソースコードが存在するのは、人間が読む必要があるからです。
もしプログラムを生成・保守するのが AI なら、人間が読めるソースは中間ステップにすぎません — 誰も頼んでいない「翻訳レイヤー」です。

**それを取り除いたらどうなるか？**

従来のフロー:

```
AI がソースコードを書く → アセンブラ/コンパイラ → バイナリ
```

このプロジェクトが試すこと:

```
AI がアノテーション付き hex を書く → hex→バイト変換器 → バイナリ
```

アセンブラなし。コンパイラなし。`.asm` ファイルなし。AI はアノテーション付き hex として、バイトを直接読み書きします。

### しくみ

**「ソース」: `game.rom.txt`** — 唯一の真実は、プレーンテキストのアノテーション付き hex ダンプです。AI は 6502 マシンコードを生の hex バイトとして書き、コメントだけがドキュメントになります。ニーモニックもラベルもアセンブラ指示子もありません。

**変換器: `generate.py`** — 約100行の Python スクリプト。やることは1つだけ: `game.rom.txt` を解析して `game.nes` を書き出す。翻訳もコンパイルもなし。各バイトを `int(token, 16)` するだけ。

```bash
uv run generate.py
# → game.nes (24592 バイト, iNES 形式)
```

**出力: `game.nes`** — どの NES エミュレータでも動く、正当な NES ROM。

### ブラウザで遊ぶ

付属のエミュレータ（Rust → WebAssembly）で、生成した ROM をブラウザで直接実行できます — 「AI が hex を書く」から「ゲームがブラウザで動く」までのループが閉じます。

**[▶ ブラウザで遊ぶ](https://nob-git-dev.github.io/vibe-whims/)**

`game.nes` を含む任意の Mapper 0 (NROM) の `.nes` ファイルを読み込めます。

| キー | NES ボタン |
|-----|-----------|
| 矢印キー | 十字キー |
| Z | B |
| X | A |
| Shift | Select |
| Enter | Start |

### リポジトリ構成

```
game.rom.txt          ← 「ソース」。AI が読み書きする。
game.nes              ← 出力。配布するのはこれ。
generate.py           ← 変換器。hex → バイト、それだけ。
domain/               ← Python ドメイン層（パーサ・ビルダ）
tests/                ← 変換器のユニットテスト
emulator/             ← Rust→WASM NES エミュレータ（ブラウザ）
```

### なぜ NES？

- 6502 命令セットは小さく（約150命令）、AI が生のオペコードを推論するのが現実的。
- iNES 形式はよく文書化され、固定でシンプルな構造を持つ。
- Mapper 0 (NROM) はバンク切替が不要 — 書いたものがそのまま出力になる。
- 数十年分のエミュレータがあるため、出力をすぐ検証できる。

### ステータス

- [x] AI が書いた `game.rom.txt` → 正当な `.nes` ROM
- [x] プレイヤースプライト・敵・当たり判定・コントローラ入力
- [x] ブラウザベースのエミュレータ（Rust → WASM）
- [ ] より複雑なプログラム（スクロール・複数の敵・スコア表示）
- [ ] 実験ログ: 何が壊れ、何が動き、何に驚いたか

*AIネイティブなバイナリ生成の実験。ソースコードは不要。*
