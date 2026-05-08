/**
 * romLoader.ts
 * <input type="file"> の change イベントから Uint8Array を取得し
 * コールバックへ渡す
 */

export function setupRomLoader(
  inputElement: HTMLInputElement,
  onRomLoaded: (data: Uint8Array, filename: string) => void,
  onError: (msg: string) => void
): void {
  inputElement.addEventListener("change", () => {
    const file = inputElement.files?.[0];
    if (!file) return;

    const reader = new FileReader();

    reader.onload = (event) => {
      const arrayBuffer = event.target?.result;
      if (!(arrayBuffer instanceof ArrayBuffer)) {
        onError("ファイルの読み取りに失敗しました");
        return;
      }
      const data = new Uint8Array(arrayBuffer);
      onRomLoaded(data, file.name);
    };

    reader.onerror = () => {
      onError("ファイルの読み取りエラー: " + file.name);
    };

    reader.readAsArrayBuffer(file);
  });
}
