export interface CanvasTextMetrics {
  width: number;
}

export interface CanvasDrawContext {
  width?: number;
  height?: number;
  fillStyle: string | number | Object;
  strokeStyle: string | number | Object;
  lineWidth: number;
  globalAlpha: number;
  lineCap: string;
  lineJoin: string;
  font: string;
  textBaseline: string;
  textAlign: string;

  save(): void;
  restore(): void;
  clearRect(x: number, y: number, width: number, height: number): void;
  fillRect(x: number, y: number, width: number, height: number): void;
  strokeRect(x: number, y: number, width: number, height: number): void;
  drawImage(image: Object, x: number, y: number, width: number, height: number): void;
  fillText(text: string, x: number, y: number): void;
  measureText(text: string): CanvasTextMetrics;
  translate(x: number, y: number): void;
  scale(x: number, y: number): void;
  beginPath(): void;
  moveTo(x: number, y: number): void;
  lineTo(x: number, y: number): void;
  quadraticCurveTo(cpx: number, cpy: number, x: number, y: number): void;
  arc(x: number, y: number, radius: number, startAngle: number, endAngle: number): void;
  drawImage(image: Object, dx: number, dy: number, dWidth: number, dHeight: number): void;
  stroke(): void;
  fill(): void;
}
