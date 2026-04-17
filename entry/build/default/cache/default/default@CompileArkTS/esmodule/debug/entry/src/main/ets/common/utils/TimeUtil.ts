export class TimeUtil {
    static now(): number {
        return Date.now();
    }
    static toIsoString(timestamp: number): string {
        return new Date(timestamp).toISOString();
    }
    static isValidTimestamp(timestamp: number): boolean {
        return !Number.isNaN(timestamp) && Number.isFinite(timestamp) && timestamp >= 0;
    }
}
