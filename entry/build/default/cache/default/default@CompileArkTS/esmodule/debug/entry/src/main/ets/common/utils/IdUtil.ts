export class IdUtil {
    private static sequence: number = 0;
    static createId(prefix: string): string {
        IdUtil.sequence += 1;
        const timePart: string = Date.now().toString(36);
        const randomPart: string = Math.floor(Math.random() * 1679616).toString(36);
        const sequencePart: string = IdUtil.sequence.toString(36);
        return `${prefix}_${timePart}_${randomPart}_${sequencePart}`;
    }
    static createNotebookId(): string {
        return IdUtil.createId('notebook');
    }
}
