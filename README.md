# vibe-whims — NES Binary Experiment

Experimental tools & random prototypes born from pure Vibe Coding whims. No plans, just vibes. Feel free to fork, break, or get inspired.

---

## 🎮 NES Emulator (Rust → WebAssembly)

A NES emulator that runs in the browser via WebAssembly.

**[▶ Play in Browser](https://nob-git-dev.github.io/vibe-whims/)**

- 6502 CPU emulation (all official instructions)
- PPU rendering (sprites, palettes, 256×240 canvas)
- Mapper 0 (NROM) support
- Keyboard input → NES gamepad mapping

### Controls

| Key | NES Button |
|-----|-----------|
| Arrow keys | D-Pad |
| Z | B |
| X | A |
| Shift | Select |
| Enter | Start |

### Local Development

```bash
cd emulator/frontend

# Build WASM (first time or after Rust changes)
pnpm run wasm:build

# Start dev server
pnpm dev
```

---

## 🔧 NES ROM Generator (Python)

Generates `.nes` ROM files directly from annotated hex dumps (`game.rom.txt`), without an assembler or compiler.

```bash
uv run generate.py
```
