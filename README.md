# NES Binary Experiment

> **Can AI output binary directly — without writing source code?**

This project is an experiment to answer that question.

---

## The Idea

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

---

## How It Works

### The "Source": `game.rom.txt`

The only source of truth is a plain-text annotated hex dump:

```
[header]
4E 45 53 1A  # iNES magic
01           # PRG-ROM banks
01           # CHR-ROM banks
00 00 00 00 00 00 00 00 00 00  # flags + padding

[prg_rom]
A9 00        # LDA #$00  — zero accumulator
85 00        # STA $00   — clear NMI flag
...

[chr_rom]
FF 81 81 81 FF 00 00 00  # player sprite (plane 0)
...

[vectors]
B1 80        # NMI  vector → $80B1
00 80        # RESET vector → $8000
C5 80        # IRQ  vector → $80C5
```

The AI writes 6502 machine code as raw hex bytes, with comments as the only documentation. No mnemonics, no labels, no assembler directives.

### The Converter: `generate.py`

A ~100-line Python script. It does exactly one thing: parse `game.rom.txt` and write `game.nes`.

No translation. No compilation. Just `int(token, 16)` for each byte.

```bash
uv run generate.py
# → game.nes (24592 bytes, iNES format)
```

### The Output: `game.nes`

A valid NES ROM that runs on any NES emulator.

---

## Play in the Browser

The companion emulator (Rust → WebAssembly) lets you run the generated ROM directly in the browser — closing the loop from "AI writes hex" to "game runs in browser."

**[▶ Play in Browser](https://nob-git-dev.github.io/vibe-whims/)**

Load any Mapper 0 (NROM) `.nes` file, including `game.nes` from this repo.

### Controls

| Key | NES Button |
|-----|-----------|
| Arrow keys | D-Pad |
| Z | B |
| X | A |
| Shift | Select |
| Enter | Start |

---

## Repository Structure

```
game.rom.txt          ← The "source". AI reads and writes this.
game.nes              ← The output. Distribute this.
generate.py           ← The converter. hex → bytes, nothing more.
domain/               ← Python domain layer (parser, builder)
tests/                ← Unit tests for the converter
emulator/             ← Rust→WASM NES emulator (browser)
```

---

## Why NES?

- The 6502 instruction set is small (~150 instructions), making it feasible for an AI to reason about raw opcodes.
- The iNES format is well-documented and has a fixed, simple structure.
- Mapper 0 (NROM) requires no bank switching — what you write is what you get.
- Decades of emulators mean the output is immediately verifiable.

---

## Status

- [x] AI-written `game.rom.txt` → valid `.nes` ROM
- [x] Player sprite, enemy, collision detection, controller input
- [x] Browser-based emulator (Rust → WASM)
- [ ] More complex programs (scrolling, multiple enemies, score display)
- [ ] Experiment log: what breaks, what works, what surprises

---

*An experiment in AI-native binary generation. No source code required.*
