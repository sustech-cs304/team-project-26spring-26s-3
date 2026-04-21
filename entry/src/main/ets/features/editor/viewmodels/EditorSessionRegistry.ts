import common from '@ohos.app.ability.common';

import { DrawingEditorViewModel } from './DrawingEditorViewModel';

export class EditorSessionRegistry {
  private static readonly sessions: Map<string, DrawingEditorViewModel> = new Map<string, DrawingEditorViewModel>();

  static getOrCreate(pageId: string, context: common.Context): DrawingEditorViewModel {
    const existingSession = this.sessions.get(pageId);
    if (existingSession) {
      return existingSession;
    }

    const nextSession = new DrawingEditorViewModel(() => context);
    this.sessions.set(pageId, nextSession);
    return nextSession;
  }

  static get(pageId: string): DrawingEditorViewModel | null {
    const existingSession = this.sessions.get(pageId);
    return existingSession === undefined ? null : existingSession;
  }

  static clear(pageId: string): void {
    this.sessions.delete(pageId);
  }

  static clearAll(): void {
    this.sessions.clear();
  }
}
