import { NES, Controller } from 'jsnes'

const canvas = document.getElementById('screen') as HTMLCanvasElement
const ctx = canvas.getContext('2d')!
const imageData = ctx.createImageData(256, 240)

const nes = new NES({
  onFrame: (frameBuffer: number[]) => {
    for (let i = 0; i < 256 * 240; i++) {
      const pixel = frameBuffer[i]
      imageData.data[i * 4]     = (pixel >> 16) & 0xFF  // R
      imageData.data[i * 4 + 1] = (pixel >> 8)  & 0xFF  // G
      imageData.data[i * 4 + 2] =  pixel        & 0xFF  // B
      imageData.data[i * 4 + 3] = 0xFF                  // A
    }
    ctx.putImageData(imageData, 0, 0)
  },
  onAudioSample: (_l: number, _r: number) => {
    // 音声は今回スキップ
  }
})

const keyMap: Record<string, number> = {
  'ArrowUp':    Controller.BUTTON_UP,
  'ArrowDown':  Controller.BUTTON_DOWN,
  'ArrowLeft':  Controller.BUTTON_LEFT,
  'ArrowRight': Controller.BUTTON_RIGHT,
  'z':          Controller.BUTTON_A,
  'x':          Controller.BUTTON_B,
  'Enter':      Controller.BUTTON_START,
  'Shift':      Controller.BUTTON_SELECT,
}

window.addEventListener('keydown', (e) => {
  const btn = keyMap[e.key]
  if (btn !== undefined) {
    e.preventDefault()
    nes.buttonDown(1, btn)
  }
})

window.addEventListener('keyup', (e) => {
  const btn = keyMap[e.key]
  if (btn !== undefined) {
    nes.buttonUp(1, btn)
  }
})

async function main(): Promise<void> {
  const response = await fetch('/game.nes')
  const buffer = await response.arrayBuffer()
  const bytes = new Uint8Array(buffer)
  const romData = Array.from(bytes).map(b => String.fromCharCode(b)).join('')
  nes.loadROM(romData)

  function frame(): void {
    nes.frame()
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}

main().catch(console.error)
