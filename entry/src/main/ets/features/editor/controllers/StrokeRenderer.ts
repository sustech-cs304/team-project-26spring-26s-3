import { getDistance } from '../../../common/utils/GeometryUtil';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { DrawableToolType } from '../../../domain/entities/ToolSetting';

interface RenderPoint {
  x: number;
  y: number;
  t: number;
  pressure: number;
}

interface RenderSample extends RenderPoint {
  velocity: number;
  width: number;
  alpha: number;
  tangentX: number;
  tangentY: number;
  normalX: number;
  normalY: number;
}

interface BrushProfile {
  minWidthFactor: number;
  maxWidthFactor: number;
  pressureFactor: number;
  velocityFactor: number;
  resampleSpacingFactor: number;
  widthBlend: number;
  velocityBlend: number;
  baseAlpha: number;
}

interface BrushPass {
  widthScale: number;
  alphaScale: number;
  jitter: number;
  widthJitter: number;
  alphaJitter: number;
  normalOffsetFactor: number;
}

type BrushLineCap = 'round' | 'butt';

const PEN_PROFILE: BrushProfile = {
  minWidthFactor: 0.52,
  maxWidthFactor: 1.22,
  pressureFactor: 0.54,
  velocityFactor: 2.9,
  resampleSpacingFactor: 0.22,
  widthBlend: 0.42,
  velocityBlend: 0.3,
  baseAlpha: 0.96
};

const PENCIL_PROFILE: BrushProfile = {
  minWidthFactor: 0.42,
  maxWidthFactor: 1.04,
  pressureFactor: 0.68,
  velocityFactor: 1.7,
  resampleSpacingFactor: 0.18,
  widthBlend: 0.34,
  velocityBlend: 0.22,
  baseAlpha: 0.34
};

const HIGHLIGHTER_PROFILE: BrushProfile = {
  minWidthFactor: 0.92,
  maxWidthFactor: 1.1,
  pressureFactor: 0.14,
  velocityFactor: 0.74,
  resampleSpacingFactor: 0.34,
  widthBlend: 0.58,
  velocityBlend: 0.36,
  baseAlpha: 0.24
};

const PEN_PASSES: BrushPass[] = [
  { widthScale: 1, alphaScale: 1, jitter: 0.004, widthJitter: 0.02, alphaJitter: 0.02, normalOffsetFactor: 0 },
  { widthScale: 0.72, alphaScale: 0.16, jitter: 0.01, widthJitter: 0.04, alphaJitter: 0.05, normalOffsetFactor: 0 }
];

const PENCIL_PASSES: BrushPass[] = [
  { widthScale: 0.86, alphaScale: 0.8, jitter: 0.03, widthJitter: 0.08, alphaJitter: 0.12, normalOffsetFactor: 0 },
  { widthScale: 0.58, alphaScale: 0.64, jitter: 0.05, widthJitter: 0.14, alphaJitter: 0.16, normalOffsetFactor: 0.06 },
  { widthScale: 0.46, alphaScale: 0.52, jitter: 0.07, widthJitter: 0.18, alphaJitter: 0.2, normalOffsetFactor: -0.08 },
  { widthScale: 0.24, alphaScale: 0.34, jitter: 0.12, widthJitter: 0.28, alphaJitter: 0.28, normalOffsetFactor: 0.14 }
];

const HIGHLIGHTER_PASSES: BrushPass[] = [
  { widthScale: 1.16, alphaScale: 0.44, jitter: 0.01, widthJitter: 0.03, alphaJitter: 0.04, normalOffsetFactor: -0.18 },
  { widthScale: 1.08, alphaScale: 0.72, jitter: 0.008, widthJitter: 0.03, alphaJitter: 0.03, normalOffsetFactor: 0 },
  { widthScale: 1.16, alphaScale: 0.44, jitter: 0.01, widthJitter: 0.03, alphaJitter: 0.04, normalOffsetFactor: 0.18 }
];

const PREVIEW_PEN_PASSES: BrushPass[] = [
  { widthScale: 1, alphaScale: 1.02, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: 0 }
];

const PREVIEW_PENCIL_PASSES: BrushPass[] = [
  { widthScale: 0.86, alphaScale: 1.9, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: 0 }
];

const PREVIEW_HIGHLIGHTER_PASSES: BrushPass[] = [
  { widthScale: 1.08, alphaScale: 1.22, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: 0 }
];

const MIN_RESAMPLE_SPACING = 0.75;
const MIN_DT = 4;
const MIN_RENDER_WIDTH = 0.8;
const MIN_PRESSURE = 0.12;
const HASH_OFFSET = 2166136261;
export class StrokeRenderer {
  static drawStroke(context: CanvasRenderingContext2D, stroke: Stroke): void {
    if (stroke.points.length === 0) {
      return;
    }

    const profile = this.getProfile(stroke.style.tool);
    const renderPoints = this.buildRenderPoints(stroke.points, stroke.style.width, profile);
    if (renderPoints.length === 0) {
      return;
    }

    const samples = this.buildRenderSamples(renderPoints, stroke.style.width, profile);
    if (samples.length === 0) {
      return;
    }

    const strokeSeed = this.hashString(stroke.id);
    const passes = this.getBrushPasses(stroke.style.tool);
    this.drawBrushPasses(context, stroke.style.tool, stroke.style.color, stroke.style.opacity, strokeSeed, samples, passes);
  }

  static drawPreviewStroke(context: CanvasRenderingContext2D, stroke: Stroke): void {
    if (stroke.points.length === 0) {
      return;
    }

    const profile = this.getProfile(stroke.style.tool);
    const renderPoints = this.buildRenderPoints(stroke.points, stroke.style.width, profile);
    if (renderPoints.length === 0) {
      return;
    }

    const samples = this.buildRenderSamples(renderPoints, stroke.style.width, profile);
    if (samples.length === 0) {
      return;
    }

    const previewPasses = this.getPreviewPasses(stroke.style.tool);
    this.drawBrushPasses(context, stroke.style.tool, stroke.style.color, stroke.style.opacity, 0, samples, previewPasses);
  }

  private static getProfile(tool: DrawableToolType): BrushProfile {
    switch (tool) {
      case 'pen':
        return PEN_PROFILE;
      case 'pencil':
        return PENCIL_PROFILE;
      case 'highlighter':
        return HIGHLIGHTER_PROFILE;
      default:
        return PEN_PROFILE;
    }
  }

  private static getBrushPasses(tool: DrawableToolType): BrushPass[] {
    switch (tool) {
      case 'pen':
        return PEN_PASSES;
      case 'pencil':
        return PENCIL_PASSES;
      case 'highlighter':
        return HIGHLIGHTER_PASSES;
      default:
        return PEN_PASSES;
    }
  }

  private static getPreviewPasses(tool: DrawableToolType): BrushPass[] {
    switch (tool) {
      case 'pencil':
        return PREVIEW_PENCIL_PASSES;
      case 'highlighter':
        return PREVIEW_HIGHLIGHTER_PASSES;
      case 'pen':
      default:
        return PREVIEW_PEN_PASSES;
    }
  }

  private static buildRenderPoints(points: StrokePoint[], baseWidth: number, profile: BrushProfile): RenderPoint[] {
    const normalizedPoints = this.normalizeInputPoints(points);
    if (normalizedPoints.length === 0) {
      return [];
    }

    const smoothedPoints = this.buildSplinePoints(normalizedPoints, baseWidth);
    const spacing = Math.max(MIN_RESAMPLE_SPACING, baseWidth * profile.resampleSpacingFactor);
    return this.resamplePoints(smoothedPoints, spacing);
  }

  private static normalizeInputPoints(points: StrokePoint[]): RenderPoint[] {
    const normalized: RenderPoint[] = [];

    for (const point of points) {
      normalized.push({
        x: point.x,
        y: point.y,
        t: point.t,
        pressure: this.resolvePressure(point.pressure)
      });
    }

    return normalized;
  }

  private static buildSplinePoints(points: RenderPoint[], baseWidth: number): RenderPoint[] {
    if (points.length <= 2) {
      return points.map((point: RenderPoint) => this.cloneRenderPoint(point));
    }

    const smoothed: RenderPoint[] = [this.cloneRenderPoint(points[0])];

    for (let index = 0; index < points.length - 1; index += 1) {
      const p0 = index === 0 ? points[0] : points[index - 1];
      const p1 = points[index];
      const p2 = points[index + 1];
      const p3 = index + 2 < points.length ? points[index + 2] : points[points.length - 1];
      const segmentDistance = getDistance(p1, p2);
      const subdivisions = Math.max(4, Math.ceil(segmentDistance / Math.max(1, baseWidth * 0.42)));

      for (let segmentIndex = 1; segmentIndex <= subdivisions; segmentIndex += 1) {
        smoothed.push(this.catmullRomPoint(p0, p1, p2, p3, segmentIndex / subdivisions));
      }
    }

    return smoothed;
  }

  private static resamplePoints(points: RenderPoint[], spacing: number): RenderPoint[] {
    if (points.length === 0) {
      return [];
    }

    if (points.length === 1) {
      return [this.cloneRenderPoint(points[0])];
    }

    const safeSpacing = Math.max(MIN_RESAMPLE_SPACING, spacing);
    const sampled: RenderPoint[] = [this.cloneRenderPoint(points[0])];
    let accumulatedDistance = 0;

    for (let index = 1; index < points.length; index += 1) {
      let segmentStart = this.cloneRenderPoint(points[index - 1]);
      const segmentEnd = this.cloneRenderPoint(points[index]);
      let segmentDistance = getDistance(segmentStart, segmentEnd);

      if (segmentDistance === 0) {
        continue;
      }

      while (accumulatedDistance + segmentDistance >= safeSpacing) {
        const remainingDistance = safeSpacing - accumulatedDistance;
        const ratio = remainingDistance / segmentDistance;
        const interpolated = this.interpolateRenderPoint(segmentStart, segmentEnd, ratio);
        sampled.push(interpolated);
        segmentStart = interpolated;
        segmentDistance = getDistance(segmentStart, segmentEnd);
        accumulatedDistance = 0;
      }

      accumulatedDistance += segmentDistance;
    }

    const finalPoint = points[points.length - 1];
    const lastPoint = sampled[sampled.length - 1];
    if (getDistance(lastPoint, finalPoint) > 0.05) {
      sampled.push(this.cloneRenderPoint(finalPoint));
    }

    return sampled;
  }

  private static buildRenderSamples(points: RenderPoint[], baseWidth: number, profile: BrushProfile): RenderSample[] {
    const samples: RenderSample[] = [];

    for (let index = 0; index < points.length; index += 1) {
      const current = points[index];
      const previousPoint = index === 0 ? current : points[index - 1];
      const nextPoint = index + 1 < points.length ? points[index + 1] : current;
      const directionX = nextPoint.x - previousPoint.x;
      const directionY = nextPoint.y - previousPoint.y;
      const directionLength = Math.sqrt(directionX * directionX + directionY * directionY);

      let tangentX = 1;
      let tangentY = 0;

      if (directionLength > 0) {
        tangentX = directionX / directionLength;
        tangentY = directionY / directionLength;
      } else if (samples.length > 0) {
        tangentX = samples[samples.length - 1].tangentX;
        tangentY = samples[samples.length - 1].tangentY;
      }

      const normalX = -tangentY;
      const normalY = tangentX;

      let instantaneousVelocity = 0;
      if (index > 0) {
        const distance = getDistance(previousPoint, current);
        const deltaTime = Math.max(MIN_DT, current.t - previousPoint.t);
        instantaneousVelocity = distance / deltaTime;
      }

      const smoothedVelocity = samples.length === 0
        ? instantaneousVelocity
        : this.lerp(samples[samples.length - 1].velocity, instantaneousVelocity, profile.velocityBlend);

      const pressureFactor = 1 + (current.pressure - 0.5) * 2 * profile.pressureFactor;
      const velocityFactor = 0.72 + 0.48 / (1 + smoothedVelocity * profile.velocityFactor);
      const targetWidth = baseWidth * this.clamp(
        pressureFactor * velocityFactor,
        profile.minWidthFactor,
        profile.maxWidthFactor
      );

      const width = samples.length === 0
        ? targetWidth
        : this.lerp(samples[samples.length - 1].width, targetWidth, profile.widthBlend);

      const alpha = this.clamp(
        profile.baseAlpha * (0.84 + current.pressure * 0.34),
        0.04,
        1
      );

      samples.push({
        x: current.x,
        y: current.y,
        t: current.t,
        pressure: current.pressure,
        velocity: smoothedVelocity,
        width,
        alpha,
        tangentX,
        tangentY,
        normalX,
        normalY
      });
    }

    return samples;
  }

  private static drawBrushPasses(
    context: CanvasRenderingContext2D,
    tool: DrawableToolType,
    color: string,
    strokeOpacity: number,
    strokeSeed: number,
    samples: RenderSample[],
    passes: BrushPass[]
  ): void {
    const lineCap = tool === 'highlighter' ? 'butt' : 'round';

    for (let passIndex = 0; passIndex < passes.length; passIndex += 1) {
      const pass = passes[passIndex];

      if (samples.length === 1) {
        this.drawSingleSample(context, color, lineCap, strokeOpacity, strokeSeed, samples[0], pass, passIndex);
        continue;
      }

      for (let sampleIndex = 1; sampleIndex < samples.length; sampleIndex += 1) {
        const startSample = samples[sampleIndex - 1];
        const endSample = samples[sampleIndex];
        this.drawSampleSegment(
          context,
          color,
          lineCap,
          strokeOpacity,
          strokeSeed,
          startSample,
          endSample,
          pass,
          passIndex,
          sampleIndex
        );
      }
    }

    context.globalAlpha = 1;
  }

  private static drawSingleSample(
    context: CanvasRenderingContext2D,
    color: string,
    lineCap: BrushLineCap,
    strokeOpacity: number,
    strokeSeed: number,
    sample: RenderSample,
    pass: BrushPass,
    passIndex: number
  ): void {
    const position = this.offsetSamplePoint(sample, pass, strokeSeed, passIndex, 0);
    const widthNoise = this.unitNoise(strokeSeed, passIndex, 0, 1);
    const alphaNoise = this.unitNoise(strokeSeed, passIndex, 0, 2);
    const lineWidth = Math.max(
      MIN_RENDER_WIDTH,
      sample.width * pass.widthScale * (1 + this.centeredNoise(widthNoise) * pass.widthJitter)
    );
    const alpha = this.clamp(
      strokeOpacity * sample.alpha * pass.alphaScale * (1 + this.centeredNoise(alphaNoise) * pass.alphaJitter),
      0.02,
      1
    );

    context.strokeStyle = color;
    context.lineCap = lineCap;
    context.lineJoin = 'round';
    context.lineWidth = lineWidth;
    context.globalAlpha = alpha;
    context.beginPath();
    context.moveTo(position.x, position.y);
    context.lineTo(position.x + 0.01, position.y + 0.01);
    context.stroke();
    context.globalAlpha = 1;
  }

  private static drawSampleSegment(
    context: CanvasRenderingContext2D,
    color: string,
    lineCap: BrushLineCap,
    strokeOpacity: number,
    strokeSeed: number,
    startSample: RenderSample,
    endSample: RenderSample,
    pass: BrushPass,
    passIndex: number,
    sampleIndex: number
  ): void {
    const startPosition = this.offsetSamplePoint(startSample, pass, strokeSeed, passIndex, sampleIndex * 2);
    const endPosition = this.offsetSamplePoint(endSample, pass, strokeSeed, passIndex, sampleIndex * 2 + 1);
    const widthNoise = this.unitNoise(strokeSeed, passIndex, sampleIndex, 3);
    const alphaNoise = this.unitNoise(strokeSeed, passIndex, sampleIndex, 4);
    const segmentWidth = Math.max(
      MIN_RENDER_WIDTH,
      ((startSample.width + endSample.width) / 2) * pass.widthScale *
        (1 + this.centeredNoise(widthNoise) * pass.widthJitter)
    );
    const segmentAlpha = this.clamp(
      strokeOpacity * ((startSample.alpha + endSample.alpha) / 2) * pass.alphaScale *
        (1 + this.centeredNoise(alphaNoise) * pass.alphaJitter),
      0.02,
      1
    );

    context.strokeStyle = color;
    context.lineCap = lineCap;
    context.lineJoin = 'round';
    context.lineWidth = segmentWidth;
    context.globalAlpha = segmentAlpha;
    context.beginPath();
    context.moveTo(startPosition.x, startPosition.y);
    context.lineTo(endPosition.x, endPosition.y);
    context.stroke();
    context.globalAlpha = 1;
  }

  private static offsetSamplePoint(
    sample: RenderSample,
    pass: BrushPass,
    strokeSeed: number,
    passIndex: number,
    sampleIndex: number
  ): { x: number; y: number } {
    const baseOffset = sample.width * pass.normalOffsetFactor;
    const normalNoise = this.centeredNoise(this.unitNoise(strokeSeed, passIndex, sampleIndex, 5));
    const tangentNoise = this.centeredNoise(this.unitNoise(strokeSeed, passIndex, sampleIndex, 6));
    const normalOffset = baseOffset + sample.width * pass.jitter * normalNoise;
    const tangentOffset = sample.width * pass.jitter * 0.35 * tangentNoise;

    return {
      x: sample.x + sample.normalX * normalOffset + sample.tangentX * tangentOffset,
      y: sample.y + sample.normalY * normalOffset + sample.tangentY * tangentOffset
    };
  }

  private static catmullRomPoint(
    p0: RenderPoint,
    p1: RenderPoint,
    p2: RenderPoint,
    p3: RenderPoint,
    ratio: number
  ): RenderPoint {
    const ratioSquared = ratio * ratio;
    const ratioCubed = ratioSquared * ratio;

    return {
      x: this.catmullRomInterpolate(p0.x, p1.x, p2.x, p3.x, ratio, ratioSquared, ratioCubed),
      y: this.catmullRomInterpolate(p0.y, p1.y, p2.y, p3.y, ratio, ratioSquared, ratioCubed),
      t: this.catmullRomInterpolate(p0.t, p1.t, p2.t, p3.t, ratio, ratioSquared, ratioCubed),
      pressure: this.clamp(
        this.catmullRomInterpolate(
          p0.pressure,
          p1.pressure,
          p2.pressure,
          p3.pressure,
          ratio,
          ratioSquared,
          ratioCubed
        ),
        MIN_PRESSURE,
        1
      )
    };
  }

  private static catmullRomInterpolate(
    v0: number,
    v1: number,
    v2: number,
    v3: number,
    ratio: number,
    ratioSquared: number,
    ratioCubed: number
  ): number {
    return 0.5 * (
      (2 * v1) +
      (-v0 + v2) * ratio +
      (2 * v0 - 5 * v1 + 4 * v2 - v3) * ratioSquared +
      (-v0 + 3 * v1 - 3 * v2 + v3) * ratioCubed
    );
  }

  private static interpolateRenderPoint(start: RenderPoint, end: RenderPoint, ratio: number): RenderPoint {
    return {
      x: this.lerp(start.x, end.x, ratio),
      y: this.lerp(start.y, end.y, ratio),
      t: this.lerp(start.t, end.t, ratio),
      pressure: this.lerp(start.pressure, end.pressure, ratio)
    };
  }

  private static resolvePressure(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value)) {
      return 0.5;
    }

    return this.clamp(value, MIN_PRESSURE, 1);
  }

  private static unitNoise(strokeSeed: number, passIndex: number, sampleIndex: number, channel: number): number {
    let hash = strokeSeed >>> 0;
    hash ^= (passIndex + 1) * 374761393;
    hash = Math.imul(hash, 668265263);
    hash ^= (sampleIndex + 1) * 2246822519;
    hash = Math.imul(hash, 3266489917);
    hash ^= (channel + 1) * 374761393;
    hash ^= hash >>> 13;
    hash = Math.imul(hash, 1274126177);
    hash ^= hash >>> 16;
    return (hash >>> 0) / 4294967295;
  }

  private static centeredNoise(value: number): number {
    return value * 2 - 1;
  }

  private static hashString(value: string): number {
    let hash = HASH_OFFSET;

    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }

    return hash >>> 0;
  }

  private static cloneRenderPoint(point: RenderPoint): RenderPoint {
    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: point.pressure
    };
  }

  private static lerp(start: number, end: number, ratio: number): number {
    return start + (end - start) * ratio;
  }

  private static clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }
}
