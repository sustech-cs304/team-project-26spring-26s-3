export interface ElementFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ElementBounds {
  width: number;
  height: number;
}

export function clampElementFrameToBounds(frame: ElementFrame, bounds: ElementBounds): ElementFrame {
  const boundsWidth = Math.max(1, bounds.width);
  const boundsHeight = Math.max(1, bounds.height);
  const width = Math.min(Math.max(1, frame.width), boundsWidth);
  const height = Math.min(Math.max(1, frame.height), boundsHeight);
  const maxX = Math.max(0, boundsWidth - width);
  const maxY = Math.max(0, boundsHeight - height);

  return {
    x: clampNumber(frame.x, 0, maxX),
    y: clampNumber(frame.y, 0, maxY),
    width,
    height
  };
}

function clampNumber(value: number, minValue: number, maxValue: number): number {
  if (!Number.isFinite(value)) {
    return minValue;
  }

  return Math.min(Math.max(value, minValue), maxValue);
}
