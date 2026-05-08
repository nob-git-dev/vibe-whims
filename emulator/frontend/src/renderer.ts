/**
 * renderer.ts
 * Uint8ClampedArray フレームバッファを ImageData に変換し Canvas に描画する
 */

export class Renderer {
  private ctx: CanvasRenderingContext2D;
  private imageData: ImageData;

  constructor(canvas: HTMLCanvasElement) {
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      throw new Error("Canvas 2D context を取得できませんでした");
    }
    this.ctx = ctx;
    // NES ネイティブ解像度 256×240
    this.imageData = new ImageData(256, 240);
  }

  /**
   * フレームバッファ（RGBA、245760 bytes）を Canvas に描画する
   * @param pixels Uint8Array (256×240×4)
   */
  draw(pixels: Uint8Array): void {
    // Uint8Array → Uint8ClampedArray へコピー
    this.imageData.data.set(pixels);
    this.ctx.putImageData(this.imageData, 0, 0);
  }
}
