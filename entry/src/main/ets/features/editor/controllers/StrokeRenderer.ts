import { BoundingBox, getDistance, getStrokeRenderBoundingBox, mergeBoundingBoxes } from '../../../common/utils/GeometryUtil';
import { getStrokeRenderKey, Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { DrawableToolType } from '../../../domain/entities/ToolSetting';
import { CanvasDrawContext } from './CanvasDrawContext';

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

export interface InProgressStrokeRenderSession {
  strokeId: string;
  styleSignature: string;
  renderKey: string;
  processedPointCount: number;
  spacing: number;
  carryDistance: number;
  lastFilteredPoint: StrokePoint | null;
  lastEmittedPoint: StrokePoint | null;
  lastEmittedVelocity: number;
  lastEmittedWidth: number;
  lastEmittedAlpha: number;
  lastEmittedTangentX: number;
  lastEmittedTangentY: number;
}

export interface IncrementalPreviewSession {
  strokeId: string;
  styleSignature: string;
  pointCount: number;
  mutableStartIndex: number;
  renderStartIndex: number;
  dirtyRect: BoundingBox | null;
}

export interface IncrementalPreviewUpdate {
  shouldDraw: boolean;
  requiresFullRedraw: boolean;
  dirtyRect: BoundingBox | null;
  promoteDirtyRect: BoundingBox | null;
  promoteStroke: Stroke | null;
  renderStroke: Stroke;
  nextSession: IncrementalPreviewSession;
}

type BrushLineCap = 'round' | 'butt';
type StrokeRenderContext = CanvasDrawContext;

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
  minWidthFactor: 0.34,
  maxWidthFactor: 0.88,
  pressureFactor: 0.76,
  velocityFactor: 0.96,
  resampleSpacingFactor: 0.14,
  widthBlend: 0.2,
  velocityBlend: 0.14,
  baseAlpha: 0.18
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
  { widthScale: 0.78, alphaScale: 0.66, jitter: 0.05, widthJitter: 0.14, alphaJitter: 0.18, normalOffsetFactor: 0 },
  { widthScale: 0.6, alphaScale: 0.54, jitter: 0.1, widthJitter: 0.22, alphaJitter: 0.26, normalOffsetFactor: 0.1 },
  { widthScale: 0.44, alphaScale: 0.42, jitter: 0.14, widthJitter: 0.3, alphaJitter: 0.34, normalOffsetFactor: -0.14 },
  { widthScale: 0.3, alphaScale: 0.24, jitter: 0.18, widthJitter: 0.38, alphaJitter: 0.42, normalOffsetFactor: 0.2 },
  { widthScale: 0.18, alphaScale: 0.16, jitter: 0.24, widthJitter: 0.46, alphaJitter: 0.5, normalOffsetFactor: -0.24 }
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
  { widthScale: 0.76, alphaScale: 0.9, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: 0 },
  { widthScale: 0.54, alphaScale: 0.42, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: 0.08 },
  { widthScale: 0.42, alphaScale: 0.24, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: -0.1 }
];

const PREVIEW_HIGHLIGHTER_PASSES: BrushPass[] = [
  { widthScale: 1.08, alphaScale: 1.22, jitter: 0, widthJitter: 0, alphaJitter: 0, normalOffsetFactor: 0 }
];

const MIN_RESAMPLE_SPACING = 0.75;
const MIN_DT = 4;
const MIN_RENDER_WIDTH = 0.8;
const MIN_PRESSURE = 0.12;
const HASH_OFFSET = 2166136261;
const CAUSAL_MIN_SMOOTHING = 0.18;
const CAUSAL_MAX_SMOOTHING = 0.72;
const CAUSAL_SMOOTHING_DISTANCE_FACTOR = 1.4;
const INCREMENTAL_PREVIEW_MUTABLE_POINT_WINDOW = 24;
const INCREMENTAL_PREVIEW_REPAIR_OVERLAP_POINTS = 12;
const INCREMENTAL_PREVIEW_STABLE_PROMOTION_STEP = 4;
export class StrokeRenderer {
  static drawStrokeFast(context: StrokeRenderContext, stroke: Stroke): void {
    this.drawRawPolyline(context, stroke);
  }

  static drawPreviewStrokeFast(context: StrokeRenderContext, stroke: Stroke): void {
    this.drawPreviewStroke(context, stroke);
  }

  static drawStroke(context: StrokeRenderContext, stroke: Stroke): void {
    const samples = this.buildVisibleSamplesForStroke(stroke);
    if (samples.length === 0) {
      return;
    }

    const strokeSeed = this.hashString(getStrokeRenderKey(stroke));
    const passes = this.getBrushPasses(stroke.style.tool);
    this.drawBrushPasses(context, stroke.style.tool, stroke.style.color, stroke.style.opacity, strokeSeed, samples, passes);
  }

  static drawPreviewStroke(context: StrokeRenderContext, stroke: Stroke): void {
    if (stroke.style.tool === 'highlighter') {
      this.drawHighlighterStroke(context, stroke);
      return;
    }

    if (stroke.style.tool === 'pencil') {
      this.drawFastPencilStroke(context, stroke);
      return;
    }

    this.drawStroke(context, stroke);
  }

  static replayInProgressStroke(
    context: CanvasDrawContext,
    stroke: Stroke
  ): InProgressStrokeRenderSession {
    let session = this.createInProgressStrokeRenderSession(stroke);
    const warmupPoints = stroke.renderWarmupPoints ?? [];
    if (warmupPoints.length === 0) {
      const result = this.consumeStrokePoints(stroke, session, stroke.points, true);
      if (result.emittedSamples.length > 0) {
        this.drawEmittedSamples(context, stroke, result.emittedSamples);
      }
      result.session.processedPointCount = stroke.points.length;
      return result.session;
    }

    session = this.consumeStrokePoints(stroke, session, warmupPoints, false).session;
    const warmResult = this.buildVisibleSamplesFromWarmSession(stroke, session);
    if (warmResult.emittedSamples.length > 0) {
      this.drawEmittedSamples(context, stroke, warmResult.emittedSamples);
    }
    warmResult.session.processedPointCount = stroke.points.length;
    return warmResult.session;
  }

  static appendInProgressStroke(
    context: CanvasDrawContext,
    stroke: Stroke,
    previousSession: InProgressStrokeRenderSession | null
  ): InProgressStrokeRenderSession {
    if (previousSession === null || !this.canContinueInProgressStroke(previousSession, stroke)) {
      return this.replayInProgressStroke(context, stroke);
    }

    const previousSample = this.restoreLastEmittedSample(previousSession);
    const nextRawPoints = stroke.points.slice(previousSession.processedPointCount);
    if (nextRawPoints.length === 0) {
      return previousSession;
    }

    const result = this.consumeStrokePoints(stroke, previousSession, nextRawPoints, true);
    if (result.emittedSamples.length > 0) {
      const samplesToDraw = previousSample === null
        ? result.emittedSamples
        : [previousSample, ...result.emittedSamples];
      this.drawEmittedSamples(context, stroke, samplesToDraw);
    }
    result.session.processedPointCount = stroke.points.length;
    return result.session;
  }

  private static buildVisibleSamplesForStroke(stroke: Stroke): RenderSample[] {
    let session = this.createInProgressStrokeRenderSession(stroke);
    const warmupPoints = stroke.renderWarmupPoints ?? [];
    if (warmupPoints.length === 0) {
      return this.consumeStrokePoints(stroke, session, stroke.points, true).emittedSamples;
    }

    session = this.consumeStrokePoints(stroke, session, warmupPoints, false).session;
    return this.buildVisibleSamplesFromWarmSession(stroke, session).emittedSamples;
  }

  private static createInProgressStrokeRenderSession(stroke: Stroke): InProgressStrokeRenderSession {
    const profile = this.getProfile(stroke.style.tool);
    return {
      strokeId: stroke.id,
      styleSignature: this.buildStyleSignature(stroke),
      renderKey: getStrokeRenderKey(stroke),
      processedPointCount: 0,
      spacing: Math.max(MIN_RESAMPLE_SPACING, stroke.style.width * profile.resampleSpacingFactor),
      carryDistance: 0,
      lastFilteredPoint: null,
      lastEmittedPoint: null,
      lastEmittedVelocity: 0,
      lastEmittedWidth: 0,
      lastEmittedAlpha: 0,
      lastEmittedTangentX: 1,
      lastEmittedTangentY: 0
    };
  }

  private static canContinueInProgressStroke(
    session: InProgressStrokeRenderSession,
    stroke: Stroke
  ): boolean {
    return session.strokeId === stroke.id &&
      session.styleSignature === this.buildStyleSignature(stroke) &&
      session.renderKey === getStrokeRenderKey(stroke) &&
      session.processedPointCount <= stroke.points.length;
  }

  private static consumeStrokePoints(
    stroke: Stroke,
    sourceSession: InProgressStrokeRenderSession,
    points: StrokePoint[],
    emitVisible: boolean
  ): { session: InProgressStrokeRenderSession; emittedSamples: RenderSample[] } {
    const profile = this.getProfile(stroke.style.tool);
    const nextSession: InProgressStrokeRenderSession = this.cloneInProgressStrokeRenderSession(sourceSession);
    const emittedSamples: RenderSample[] = [];

    for (const point of points) {
      const normalizedPoint = this.normalizeRenderPoint(point);
      if (nextSession.lastFilteredPoint === null) {
        nextSession.lastFilteredPoint = this.cloneStrokePoint(normalizedPoint);
        const firstSample = this.createFirstCausalSample(normalizedPoint, stroke.style.width, profile);
        this.applyEmittedSampleToSession(nextSession, firstSample);
        if (emitVisible) {
          emittedSamples.push(firstSample);
        }
        continue;
      }

      const previousFilteredPoint = this.toRenderPoint(nextSession.lastFilteredPoint);
      const filteredPoint = this.filterCausalPoint(previousFilteredPoint, normalizedPoint, stroke.style.width);
      this.consumeCausalSegment(
        nextSession,
        previousFilteredPoint,
        filteredPoint,
        stroke.style.width,
        profile,
        emitVisible,
        emittedSamples
      );
      nextSession.lastFilteredPoint = this.cloneStrokePoint(filteredPoint);
    }

    return {
      session: nextSession,
      emittedSamples
    };
  }

  private static consumeCausalSegment(
    session: InProgressStrokeRenderSession,
    segmentStart: RenderPoint,
    segmentEnd: RenderPoint,
    baseWidth: number,
    profile: BrushProfile,
    emitVisible: boolean,
    emittedSamples: RenderSample[]
  ): void {
    let currentStart = this.cloneRenderPoint(segmentStart);
    let remainingDistance = getDistance(currentStart, segmentEnd);
    if (remainingDistance <= 0) {
      return;
    }

    let carryDistance = session.carryDistance;
    while (carryDistance + remainingDistance >= session.spacing) {
      const nextDistance = session.spacing - carryDistance;
      const ratio = remainingDistance <= 0 ? 0 : nextDistance / remainingDistance;
      const emittedPoint = this.interpolateRenderPoint(currentStart, segmentEnd, ratio);
      const emittedSample = this.buildNextCausalSample(session, emittedPoint, baseWidth, profile);
      this.applyEmittedSampleToSession(session, emittedSample);
      if (emitVisible) {
        emittedSamples.push(emittedSample);
      }
      currentStart = emittedPoint;
      remainingDistance = getDistance(currentStart, segmentEnd);
      carryDistance = 0;
    }

    session.carryDistance = carryDistance + remainingDistance;
  }

  private static buildVisibleSamplesFromWarmSession(
    stroke: Stroke,
    session: InProgressStrokeRenderSession
  ): { session: InProgressStrokeRenderSession; emittedSamples: RenderSample[] } {
    if (stroke.points.length === 0) {
      return {
        session,
        emittedSamples: []
      };
    }

    const warmedSession = this.alignSessionToVisibleStart(session, stroke.points[0]);
    const seededSample = this.restoreLastEmittedSample(warmedSession);
    const emittedSamples: RenderSample[] = seededSample === null ? [] : [seededSample];
    if (stroke.points.length === 1) {
      return {
        session: warmedSession,
        emittedSamples
      };
    }

    const result = this.consumeStrokePoints(stroke, warmedSession, stroke.points.slice(1), true);
    return {
      session: result.session,
      emittedSamples: emittedSamples.concat(result.emittedSamples)
    };
  }

  private static alignSessionToVisibleStart(
    session: InProgressStrokeRenderSession,
    point: StrokePoint
  ): InProgressStrokeRenderSession {
    const nextSession = this.cloneInProgressStrokeRenderSession(session);
    const normalizedPoint = this.normalizeRenderPoint(point);
    nextSession.lastFilteredPoint = this.cloneStrokePoint(normalizedPoint);
    nextSession.lastEmittedPoint = this.cloneStrokePoint(normalizedPoint);
    nextSession.carryDistance = 0;
    return nextSession;
  }

  private static createFirstCausalSample(
    point: RenderPoint,
    baseWidth: number,
    profile: BrushProfile
  ): RenderSample {
    const pressureFactor = 1 + (point.pressure - 0.5) * 2 * profile.pressureFactor;
    const velocityFactor = 0.72 + 0.48;
    const width = baseWidth * this.clamp(
      pressureFactor * velocityFactor,
      profile.minWidthFactor,
      profile.maxWidthFactor
    );
    const alpha = this.clamp(
      profile.baseAlpha * (0.84 + point.pressure * 0.34),
      0.04,
      1
    );

    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: point.pressure,
      velocity: 0,
      width,
      alpha,
      tangentX: 1,
      tangentY: 0,
      normalX: 0,
      normalY: 1
    };
  }

  private static buildNextCausalSample(
    session: InProgressStrokeRenderSession,
    point: RenderPoint,
    baseWidth: number,
    profile: BrushProfile
  ): RenderSample {
    const previousSample = this.restoreLastEmittedSample(session);
    if (previousSample === null) {
      return this.createFirstCausalSample(point, baseWidth, profile);
    }

    const deltaX = point.x - previousSample.x;
    const deltaY = point.y - previousSample.y;
    const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    const deltaTime = Math.max(MIN_DT, point.t - previousSample.t);
    const tangentLength = Math.max(distance, 0.0001);
    const tangentX = distance > 0 ? deltaX / tangentLength : previousSample.tangentX;
    const tangentY = distance > 0 ? deltaY / tangentLength : previousSample.tangentY;
    const velocity = this.lerp(previousSample.velocity, distance / deltaTime, profile.velocityBlend);
    const pressureFactor = 1 + (point.pressure - 0.5) * 2 * profile.pressureFactor;
    const velocityFactor = 0.72 + 0.48 / (1 + velocity * profile.velocityFactor);
    const targetWidth = baseWidth * this.clamp(
      pressureFactor * velocityFactor,
      profile.minWidthFactor,
      profile.maxWidthFactor
    );
    const width = this.lerp(previousSample.width, targetWidth, profile.widthBlend);
    const alpha = this.clamp(
      profile.baseAlpha * (0.84 + point.pressure * 0.34),
      0.04,
      1
    );

    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: point.pressure,
      velocity,
      width,
      alpha,
      tangentX,
      tangentY,
      normalX: -tangentY,
      normalY: tangentX
    };
  }

  private static applyEmittedSampleToSession(
    session: InProgressStrokeRenderSession,
    sample: RenderSample
  ): void {
    session.lastEmittedPoint = {
      x: sample.x,
      y: sample.y,
      t: sample.t,
      pressure: sample.pressure
    };
    session.lastEmittedVelocity = sample.velocity;
    session.lastEmittedWidth = sample.width;
    session.lastEmittedAlpha = sample.alpha;
    session.lastEmittedTangentX = sample.tangentX;
    session.lastEmittedTangentY = sample.tangentY;
  }

  private static restoreLastEmittedSample(session: InProgressStrokeRenderSession): RenderSample | null {
    if (session.lastEmittedPoint === null) {
      return null;
    }

    return {
      x: session.lastEmittedPoint.x,
      y: session.lastEmittedPoint.y,
      t: session.lastEmittedPoint.t,
      pressure: this.resolvePressure(session.lastEmittedPoint.pressure),
      velocity: session.lastEmittedVelocity,
      width: session.lastEmittedWidth,
      alpha: session.lastEmittedAlpha,
      tangentX: session.lastEmittedTangentX,
      tangentY: session.lastEmittedTangentY,
      normalX: -session.lastEmittedTangentY,
      normalY: session.lastEmittedTangentX
    };
  }

  private static drawEmittedSamples(
    context: CanvasDrawContext,
    stroke: Stroke,
    samples: RenderSample[]
  ): void {
    if (samples.length === 0) {
      return;
    }

    if (stroke.style.tool === 'highlighter') {
      this.drawHighlighterSamples(context, stroke, samples);
      return;
    }

    const strokeSeed = this.hashString(getStrokeRenderKey(stroke));
    const passes = this.getBrushPasses(stroke.style.tool);
    this.drawBrushPasses(context, stroke.style.tool, stroke.style.color, stroke.style.opacity, strokeSeed, samples, passes);
  }

  private static drawHighlighterStroke(context: StrokeRenderContext, stroke: Stroke): void {
    const points = this.buildHighlighterPathPoints(stroke.points, stroke.style.width);
    if (points.length === 0) {
      return;
    }

    const lineWidth = Math.max(MIN_RENDER_WIDTH, stroke.style.width * 1.02);
    const alpha = this.clamp(stroke.style.opacity * 0.3, 0.08, 0.42);

    context.strokeStyle = stroke.style.color;
    context.lineCap = 'butt';
    context.lineJoin = 'round';
    context.lineWidth = lineWidth;
    context.globalAlpha = alpha;
    context.beginPath();
    this.traceHighlighterPoints(context, points);
    context.stroke();
    context.globalAlpha = 1;
  }

  private static drawHighlighterSamples(
    context: StrokeRenderContext,
    stroke: Stroke,
    samples: RenderSample[]
  ): void {
    if (samples.length === 0) {
      return;
    }

    const lineWidth = Math.max(MIN_RENDER_WIDTH, stroke.style.width * 1.02);
    const alpha = this.clamp(stroke.style.opacity * 0.3, 0.08, 0.42);

    context.strokeStyle = stroke.style.color;
    context.lineCap = 'butt';
    context.lineJoin = 'round';
    context.lineWidth = lineWidth;
    context.globalAlpha = alpha;
    context.beginPath();
    this.traceHighlighterPath(context, samples);
    context.stroke();
    context.globalAlpha = 1;
  }

  private static traceHighlighterPath(
    context: StrokeRenderContext,
    samples: RenderSample[]
  ): void {
    const firstSample = samples[0];
    context.moveTo(firstSample.x, firstSample.y);

    if (samples.length === 1) {
      context.lineTo(firstSample.x + 0.01, firstSample.y + 0.01);
      return;
    }

    if (samples.length === 2) {
      const lastSample = samples[1];
      context.lineTo(lastSample.x, lastSample.y);
      return;
    }

    for (let index = 1; index < samples.length - 1; index += 1) {
      const currentSample = samples[index];
      const nextSample = samples[index + 1];
      const midpointX = (currentSample.x + nextSample.x) / 2;
      const midpointY = (currentSample.y + nextSample.y) / 2;
      context.quadraticCurveTo(currentSample.x, currentSample.y, midpointX, midpointY);
    }

    const tailSample = samples[samples.length - 1];
    context.lineTo(tailSample.x, tailSample.y);
  }

  private static buildHighlighterPathPoints(points: StrokePoint[], width: number): StrokePoint[] {
    if (points.length <= 2) {
      return points;
    }

    const minimumDistance = Math.max(1.5, width * 0.45);
    const simplified: StrokePoint[] = [points[0]];
    let lastPoint = points[0];

    for (let index = 1; index < points.length - 1; index += 1) {
      const point = points[index];
      if (getDistance(lastPoint, point) >= minimumDistance) {
        simplified.push(point);
        lastPoint = point;
      }
    }

    const finalPoint = points[points.length - 1];
    if (simplified[simplified.length - 1] !== finalPoint) {
      simplified.push(finalPoint);
    }
    return simplified;
  }

  private static traceHighlighterPoints(
    context: StrokeRenderContext,
    points: StrokePoint[]
  ): void {
    const firstPoint = points[0];
    context.moveTo(firstPoint.x, firstPoint.y);

    if (points.length === 1) {
      context.lineTo(firstPoint.x + 0.01, firstPoint.y + 0.01);
      return;
    }

    if (points.length === 2) {
      const lastPoint = points[1];
      context.lineTo(lastPoint.x, lastPoint.y);
      return;
    }

    for (let index = 1; index < points.length - 1; index += 1) {
      const currentPoint = points[index];
      const nextPoint = points[index + 1];
      const midpointX = (currentPoint.x + nextPoint.x) / 2;
      const midpointY = (currentPoint.y + nextPoint.y) / 2;
      context.quadraticCurveTo(currentPoint.x, currentPoint.y, midpointX, midpointY);
    }

    const tailPoint = points[points.length - 1];
    context.lineTo(tailPoint.x, tailPoint.y);
  }

  private static drawFastPencilStroke(context: StrokeRenderContext, stroke: Stroke): void {
    if (stroke.points.length === 0) {
      return;
    }

    const points = this.buildPencilPathPoints(stroke.points, stroke.style.width, 0.22);
    context.lineCap = 'round';
    context.lineJoin = 'round';

    const passes = [
      { widthScale: 0.74, alpha: this.clamp(stroke.style.opacity * 0.34, 0.05, 0.52), offsetX: 0, offsetY: 0 },
      { widthScale: 0.5, alpha: this.clamp(stroke.style.opacity * 0.16, 0.03, 0.24), offsetX: 0.35, offsetY: -0.25 },
      { widthScale: 0.38, alpha: this.clamp(stroke.style.opacity * 0.1, 0.02, 0.16), offsetX: -0.3, offsetY: 0.3 }
    ];

    for (const pass of passes) {
      context.strokeStyle = stroke.style.color;
      context.lineWidth = Math.max(MIN_RENDER_WIDTH, stroke.style.width * pass.widthScale);
      context.globalAlpha = pass.alpha;
      context.beginPath();
      this.traceOffsetStrokePoints(context, points, pass.offsetX, pass.offsetY);
      context.stroke();
    }

    context.globalAlpha = 1;
  }

  private static drawDetailedPencilStroke(context: StrokeRenderContext, stroke: Stroke): void {
    if (stroke.points.length === 0) {
      return;
    }

    const points = this.buildPencilPathPoints(stroke.points, stroke.style.width, 0.14);
    context.lineCap = 'round';
    context.lineJoin = 'round';

    const passes = [
      { widthScale: 0.82, alpha: this.clamp(stroke.style.opacity * 0.26, 0.06, 0.42), offsetX: 0, offsetY: 0 },
      { widthScale: 0.68, alpha: this.clamp(stroke.style.opacity * 0.19, 0.04, 0.28), offsetX: 0.18, offsetY: -0.14 },
      { widthScale: 0.56, alpha: this.clamp(stroke.style.opacity * 0.14, 0.03, 0.22), offsetX: -0.16, offsetY: 0.18 },
      { widthScale: 0.44, alpha: this.clamp(stroke.style.opacity * 0.1, 0.02, 0.16), offsetX: 0.34, offsetY: 0.1 },
      { widthScale: 0.32, alpha: this.clamp(stroke.style.opacity * 0.07, 0.02, 0.12), offsetX: -0.28, offsetY: -0.2 }
    ];

    for (const pass of passes) {
      context.strokeStyle = stroke.style.color;
      context.lineWidth = Math.max(MIN_RENDER_WIDTH, stroke.style.width * pass.widthScale);
      context.globalAlpha = pass.alpha;
      context.beginPath();
      this.traceOffsetStrokePoints(context, points, pass.offsetX, pass.offsetY);
      context.stroke();
    }

    context.globalAlpha = 1;
  }

  private static buildPencilPathPoints(points: StrokePoint[], width: number, spacingFactor: number): StrokePoint[] {
    if (points.length <= 2) {
      return points;
    }

    const minimumDistance = Math.max(1.2, width * spacingFactor);
    const simplified: StrokePoint[] = [points[0]];
    let lastPoint = points[0];

    for (let index = 1; index < points.length - 1; index += 1) {
      const point = points[index];
      if (getDistance(lastPoint, point) >= minimumDistance) {
        simplified.push(point);
        lastPoint = point;
      }
    }

    const finalPoint = points[points.length - 1];
    if (simplified[simplified.length - 1] !== finalPoint) {
      simplified.push(finalPoint);
    }
    return simplified;
  }

  private static traceOffsetStrokePoints(
    context: StrokeRenderContext,
    points: StrokePoint[],
    offsetX: number,
    offsetY: number
  ): void {
    const firstPoint = points[0];
    context.moveTo(firstPoint.x + offsetX, firstPoint.y + offsetY);

    if (points.length === 1) {
      context.lineTo(firstPoint.x + offsetX + 0.01, firstPoint.y + offsetY + 0.01);
      return;
    }

    if (points.length === 2) {
      const lastPoint = points[1];
      context.lineTo(lastPoint.x + offsetX, lastPoint.y + offsetY);
      return;
    }

    for (let index = 1; index < points.length - 1; index += 1) {
      const currentPoint = points[index];
      const nextPoint = points[index + 1];
      const midpointX = (currentPoint.x + nextPoint.x) / 2;
      const midpointY = (currentPoint.y + nextPoint.y) / 2;
      context.quadraticCurveTo(
        currentPoint.x + offsetX,
        currentPoint.y + offsetY,
        midpointX + offsetX,
        midpointY + offsetY
      );
    }

    const tailPoint = points[points.length - 1];
    context.lineTo(tailPoint.x + offsetX, tailPoint.y + offsetY);
  }

  private static filterCausalPoint(
    previousPoint: RenderPoint,
    nextPoint: RenderPoint,
    baseWidth: number
  ): RenderPoint {
    const distance = getDistance(previousPoint, nextPoint);
    const smoothing = this.clamp(
      distance / Math.max(1, baseWidth * CAUSAL_SMOOTHING_DISTANCE_FACTOR),
      CAUSAL_MIN_SMOOTHING,
      CAUSAL_MAX_SMOOTHING
    );

    return {
      x: this.lerp(previousPoint.x, nextPoint.x, smoothing),
      y: this.lerp(previousPoint.y, nextPoint.y, smoothing),
      t: this.lerp(previousPoint.t, nextPoint.t, smoothing),
      pressure: this.lerp(previousPoint.pressure, nextPoint.pressure, smoothing)
    };
  }

  private static normalizeRenderPoint(point: StrokePoint): RenderPoint {
    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: this.resolvePressure(point.pressure)
    };
  }

  private static toRenderPoint(point: StrokePoint): RenderPoint {
    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: this.resolvePressure(point.pressure)
    };
  }

  private static cloneStrokePoint(point: RenderPoint): StrokePoint {
    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: point.pressure
    };
  }

  private static cloneInProgressStrokeRenderSession(
    session: InProgressStrokeRenderSession
  ): InProgressStrokeRenderSession {
    return {
      strokeId: session.strokeId,
      styleSignature: session.styleSignature,
      renderKey: session.renderKey,
      processedPointCount: session.processedPointCount,
      spacing: session.spacing,
      carryDistance: session.carryDistance,
      lastFilteredPoint: session.lastFilteredPoint === null ? null : {
        x: session.lastFilteredPoint.x,
        y: session.lastFilteredPoint.y,
        t: session.lastFilteredPoint.t,
        pressure: session.lastFilteredPoint.pressure
      },
      lastEmittedPoint: session.lastEmittedPoint === null ? null : {
        x: session.lastEmittedPoint.x,
        y: session.lastEmittedPoint.y,
        t: session.lastEmittedPoint.t,
        pressure: session.lastEmittedPoint.pressure
      },
      lastEmittedVelocity: session.lastEmittedVelocity,
      lastEmittedWidth: session.lastEmittedWidth,
      lastEmittedAlpha: session.lastEmittedAlpha,
      lastEmittedTangentX: session.lastEmittedTangentX,
      lastEmittedTangentY: session.lastEmittedTangentY
    };
  }

  static createIncrementalPreviewSession(stroke: Stroke): IncrementalPreviewSession {
    const mutableStartIndex = this.getIncrementalPreviewMutableStartIndex(stroke.points.length);
    const renderStartIndex = this.getIncrementalPreviewRenderStartIndex(mutableStartIndex);
    const visibleStroke = this.buildStrokeSlice(stroke, mutableStartIndex);

    return {
      strokeId: stroke.id,
      styleSignature: this.buildStyleSignature(stroke),
      pointCount: stroke.points.length,
      mutableStartIndex,
      renderStartIndex,
      dirtyRect: getStrokeRenderBoundingBox(visibleStroke)
    };
  }

  static buildIncrementalPreviewUpdate(
    stroke: Stroke,
    previousSession: IncrementalPreviewSession | null
  ): IncrementalPreviewUpdate {
    const nextSession = this.createIncrementalPreviewSession(stroke);
    const renderStroke = this.buildStrokeSlice(stroke, nextSession.renderStartIndex);

    if (previousSession === null) {
      return {
        shouldDraw: true,
        requiresFullRedraw: true,
        dirtyRect: nextSession.dirtyRect,
        promoteDirtyRect: null,
        promoteStroke: null,
        renderStroke,
        nextSession
      };
    }

    if (
      previousSession.strokeId !== nextSession.strokeId ||
      previousSession.styleSignature !== nextSession.styleSignature ||
      nextSession.pointCount < previousSession.pointCount
    ) {
      return {
        shouldDraw: true,
        requiresFullRedraw: true,
        dirtyRect: nextSession.dirtyRect,
        promoteDirtyRect: null,
        promoteStroke: null,
        renderStroke,
        nextSession
      };
    }

    if (nextSession.pointCount === previousSession.pointCount) {
      return {
        shouldDraw: false,
        requiresFullRedraw: false,
        dirtyRect: null,
        promoteDirtyRect: null,
        promoteStroke: null,
        renderStroke,
        nextSession: previousSession
      };
    }

    let promoteDirtyRect: BoundingBox | null = null;
    let promoteStroke: Stroke | null = null;
    if (nextSession.mutableStartIndex > previousSession.mutableStartIndex) {
      promoteDirtyRect = this.getStrokeSliceBounds(
        stroke,
        previousSession.mutableStartIndex,
        nextSession.mutableStartIndex
      );

      if (promoteDirtyRect !== null) {
        promoteStroke = this.buildStrokeRange(stroke, 0, nextSession.mutableStartIndex);
      }
    }

    return {
      shouldDraw: true,
      requiresFullRedraw: false,
      dirtyRect: mergeBoundingBoxes(previousSession.dirtyRect, nextSession.dirtyRect),
      promoteDirtyRect,
      promoteStroke,
      renderStroke,
      nextSession
    };
  }

  static buildStablePreviewStroke(stroke: Stroke): Stroke | null {
    const session = this.createIncrementalPreviewSession(stroke);
    if (session.mutableStartIndex <= 0) {
      return null;
    }

    return this.buildStrokeRange(stroke, 0, session.mutableStartIndex);
  }

  private static drawRawPolyline(context: StrokeRenderContext, stroke: Stroke): void {
    if (stroke.points.length === 0) {
      return;
    }

    const points = stroke.points;
    context.strokeStyle = stroke.style.color;
    context.lineCap = stroke.style.tool === 'highlighter' ? 'butt' : 'round';
    context.lineJoin = 'round';
    context.lineWidth = Math.max(MIN_RENDER_WIDTH, stroke.style.width);
    context.globalAlpha = this.getFastStrokeOpacity(stroke.style.tool, stroke.style.opacity);
    context.beginPath();
    context.moveTo(points[0].x, points[0].y);

    if (points.length === 1) {
      context.lineTo(points[0].x + 0.01, points[0].y + 0.01);
    } else {
      for (let index = 1; index < points.length; index += 1) {
        context.lineTo(points[index].x, points[index].y);
      }
    }

    context.stroke();
    context.globalAlpha = 1;
  }

  private static getFastStrokeOpacity(tool: DrawableToolType, opacity: number): number {
    if (tool === 'highlighter') {
      return this.clamp(opacity * 0.42, 0.08, 1);
    }

    if (tool === 'pencil') {
      return this.clamp(opacity * 0.46, 0.05, 0.72);
    }

    return this.clamp(opacity, 0.12, 1);
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
    context: StrokeRenderContext,
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
          passIndex
        );
      }
    }

    context.globalAlpha = 1;
  }

  private static drawSingleSample(
    context: StrokeRenderContext,
    color: string,
    lineCap: BrushLineCap,
    strokeOpacity: number,
    strokeSeed: number,
    sample: RenderSample,
    pass: BrushPass,
    passIndex: number
  ): void {
    const sampleNoiseBasis = this.getSampleNoiseBasis(sample);
    const position = this.offsetSamplePoint(sample, pass, strokeSeed, passIndex, sampleNoiseBasis);
    const widthNoise = this.unitNoise(strokeSeed, passIndex, 1, sampleNoiseBasis);
    const alphaNoise = this.unitNoise(strokeSeed, passIndex, 2, sampleNoiseBasis);
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
    context: StrokeRenderContext,
    color: string,
    lineCap: BrushLineCap,
    strokeOpacity: number,
    strokeSeed: number,
    startSample: RenderSample,
    endSample: RenderSample,
    pass: BrushPass,
    passIndex: number
  ): void {
    const startNoiseBasis = this.getSampleNoiseBasis(startSample);
    const endNoiseBasis = this.getSampleNoiseBasis(endSample);
    const segmentNoiseBasis = this.combineNoiseBases(startNoiseBasis, endNoiseBasis);
    const startPosition = this.offsetSamplePoint(startSample, pass, strokeSeed, passIndex, startNoiseBasis);
    const endPosition = this.offsetSamplePoint(endSample, pass, strokeSeed, passIndex, endNoiseBasis);
    const widthNoise = this.unitNoise(strokeSeed, passIndex, 3, segmentNoiseBasis);
    const alphaNoise = this.unitNoise(strokeSeed, passIndex, 4, segmentNoiseBasis);
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
    sampleNoiseBasis: number
  ): { x: number; y: number } {
    const baseOffset = sample.width * pass.normalOffsetFactor;
    const normalNoise = this.centeredNoise(this.unitNoise(strokeSeed, passIndex, 5, sampleNoiseBasis));
    const tangentNoise = this.centeredNoise(this.unitNoise(strokeSeed, passIndex, 6, sampleNoiseBasis));
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

  private static unitNoise(strokeSeed: number, passIndex: number, channel: number, noiseBasis: number): number {
    let hash = strokeSeed >>> 0;
    hash ^= noiseBasis >>> 0;
    hash = Math.imul(hash, 2246822519);
    hash ^= (passIndex + 1) * 374761393;
    hash = Math.imul(hash, 668265263);
    hash ^= (channel + 1) * 374761393;
    hash = Math.imul(hash, 3266489917);
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

  private static getSampleNoiseBasis(sample: RenderSample): number {
    let hash = HASH_OFFSET;
    hash ^= Math.round(sample.x * 16);
    hash = Math.imul(hash, 16777619);
    hash ^= Math.round(sample.y * 16);
    hash = Math.imul(hash, 16777619);
    hash ^= Math.round(sample.t / 4);
    hash = Math.imul(hash, 16777619);
    hash ^= Math.round(sample.width * 16);
    hash = Math.imul(hash, 16777619);
    return hash >>> 0;
  }

  private static combineNoiseBases(left: number, right: number): number {
    let hash = HASH_OFFSET;
    hash ^= left >>> 0;
    hash = Math.imul(hash, 16777619);
    hash ^= right >>> 0;
    hash = Math.imul(hash, 16777619);
    return hash >>> 0;
  }

  private static getIncrementalPreviewMutableStartIndex(pointCount: number): number {
    const rawMutableStartIndex = Math.max(0, pointCount - INCREMENTAL_PREVIEW_MUTABLE_POINT_WINDOW);
    if (rawMutableStartIndex <= 0) {
      return 0;
    }

    return rawMutableStartIndex - (rawMutableStartIndex % INCREMENTAL_PREVIEW_STABLE_PROMOTION_STEP);
  }

  private static getIncrementalPreviewRenderStartIndex(mutableStartIndex: number): number {
    return Math.max(0, mutableStartIndex - INCREMENTAL_PREVIEW_REPAIR_OVERLAP_POINTS);
  }

  private static buildStrokeSlice(stroke: Stroke, startIndex: number): Stroke {
    return this.buildStrokeRange(stroke, startIndex, stroke.points.length);
  }

  private static buildStrokeRange(stroke: Stroke, startIndex: number, endExclusive: number): Stroke {
    const normalizedStartIndex = Math.max(0, Math.min(startIndex, stroke.points.length));
    const normalizedEndExclusive = Math.max(normalizedStartIndex, Math.min(endExclusive, stroke.points.length));

    return {
      id: stroke.id,
      pageId: stroke.pageId,
      renderKey: stroke.renderKey,
      renderWarmupPoints: stroke.renderWarmupPoints?.map((point: StrokePoint) => ({
        x: point.x,
        y: point.y,
        t: point.t,
        pressure: point.pressure
      })) ?? [],
      points: stroke.points.slice(normalizedStartIndex, normalizedEndExclusive).map((point: StrokePoint) => ({
        x: point.x,
        y: point.y,
        t: point.t,
        pressure: point.pressure
      })),
      style: {
        tool: stroke.style.tool,
        color: stroke.style.color,
        width: stroke.style.width,
        opacity: stroke.style.opacity
      },
      createdAt: stroke.createdAt,
      updatedAt: stroke.updatedAt
    };
  }

  private static getStrokeSliceBounds(stroke: Stroke, startIndex: number, endExclusive: number): BoundingBox | null {
    const slice = this.buildStrokeRange(stroke, startIndex, endExclusive);
    if (slice.points.length === 0) {
      return null;
    }

    return getStrokeRenderBoundingBox(slice);
  }

  private static buildStyleSignature(stroke: Stroke): string {
    return `${stroke.style.tool}|${stroke.style.color}|${stroke.style.width}|${stroke.style.opacity}`;
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
