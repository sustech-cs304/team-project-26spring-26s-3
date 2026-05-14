interface PerformanceBucket {
  count: number;
  totalMs: number;
  maxMs: number;
  slowCount: number;
}

const DEFAULT_SLOW_THRESHOLD_MS = 8;
const SUMMARY_INTERVAL = 24;

export class EditorPerformanceTrace {
  private static readonly ENABLED: boolean = true;
  private static readonly buckets: Map<string, PerformanceBucket> = new Map<string, PerformanceBucket>();

  static measureSync<T>(
    label: string,
    work: () => T,
    meta: string = '',
    slowThresholdMs: number = DEFAULT_SLOW_THRESHOLD_MS
  ): T {
    const startedAt = Date.now();
    try {
      return work();
    } finally {
      this.record(label, Date.now() - startedAt, meta, slowThresholdMs);
    }
  }

  static async measureAsync<T>(
    label: string,
    work: () => Promise<T>,
    meta: string = '',
    slowThresholdMs: number = DEFAULT_SLOW_THRESHOLD_MS
  ): Promise<T> {
    const startedAt = Date.now();
    try {
      return await work();
    } finally {
      this.record(label, Date.now() - startedAt, meta, slowThresholdMs);
    }
  }

  static record(
    label: string,
    durationMs: number,
    meta: string = '',
    slowThresholdMs: number = DEFAULT_SLOW_THRESHOLD_MS
  ): void {
    if (!this.ENABLED) {
      return;
    }

    const normalizedDurationMs = Math.max(0, durationMs);
    const bucket = this.getOrCreateBucket(label);
    bucket.count += 1;
    bucket.totalMs += normalizedDurationMs;
    bucket.maxMs = Math.max(bucket.maxMs, normalizedDurationMs);

    const isSlow = normalizedDurationMs >= slowThresholdMs;
    if (isSlow) {
      bucket.slowCount += 1;
    }

    if (!isSlow && bucket.count % SUMMARY_INTERVAL !== 0) {
      return;
    }

    const averageMs = bucket.totalMs / Math.max(1, bucket.count);
    const suffix = meta.length > 0 ? ` ${meta}` : '';
    console.info(
      `[EditorPerf] ${label} ms=${normalizedDurationMs} avg=${averageMs.toFixed(1)} max=${bucket.maxMs} count=${bucket.count} slow=${bucket.slowCount}${suffix}`
    );
  }

  private static getOrCreateBucket(label: string): PerformanceBucket {
    const existingBucket = this.buckets.get(label);
    if (existingBucket !== undefined) {
      return existingBucket;
    }

    const nextBucket: PerformanceBucket = {
      count: 0,
      totalMs: 0,
      maxMs: 0,
      slowCount: 0
    };
    this.buckets.set(label, nextBucket);
    return nextBucket;
  }
}
