export interface CanvasViewport {
  offsetX: number;
  offsetY: number;
  scale: number;
}

export const defaultViewport: CanvasViewport = {
  offsetX: 0,
  offsetY: 0,
  scale: 1
};
