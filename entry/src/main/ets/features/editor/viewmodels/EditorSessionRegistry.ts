import common from '@ohos.app.ability.common';

import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { DrawingEditorViewModel } from './DrawingEditorViewModel';

export class EditorSessionRegistry {
  private static readonly sessions: Map<string, DrawingEditorViewModel> = new Map<string, DrawingEditorViewModel>();
  private static readonly loadingTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  static getOrCreate(pageId: string, context: common.Context): DrawingEditorViewModel {
    const existingSession = this.sessions.get(pageId);
    if (existingSession) {
      return existingSession;
    }

    const nextSession = new DrawingEditorViewModel(() => context);
    this.sessions.set(pageId, nextSession);
    return nextSession;
  }

  static async ensureLoaded(
    pageId: string,
    context: common.Context,
    toolSetting?: ToolSetting
  ): Promise<DrawingEditorViewModel> {
    const session = this.getOrCreate(pageId, context);
    if (toolSetting !== undefined) {
      this.applyToolSetting(session, toolSetting);
    }

    if (session.isLoadedForPage(pageId)) {
      return session;
    }

    const existingTask = this.loadingTasks.get(pageId);
    if (existingTask !== undefined) {
      await existingTask;
      return session;
    }

    const loadTask = session.loadPage(pageId);
    this.loadingTasks.set(pageId, loadTask);
    try {
      await loadTask;
      if (toolSetting !== undefined) {
        this.applyToolSetting(session, toolSetting);
      }
    } finally {
      this.loadingTasks.delete(pageId);
    }

    return session;
  }

  static get(pageId: string): DrawingEditorViewModel | null {
    const existingSession = this.sessions.get(pageId);
    return existingSession === undefined ? null : existingSession;
  }

  static updateToolSettingForAll(toolSetting: ToolSetting): void {
    this.sessions.forEach((session: DrawingEditorViewModel): void => {
      this.applyToolSetting(session, toolSetting);
    });
  }

  static clear(pageId: string): void {
    this.sessions.delete(pageId);
    this.loadingTasks.delete(pageId);
  }

  static clearAll(): void {
    this.sessions.clear();
    this.loadingTasks.clear();
  }

  private static applyToolSetting(session: DrawingEditorViewModel, toolSetting: ToolSetting): void {
    const currentSetting = session.getToolSetting();
    if (currentSetting.tool === toolSetting.tool &&
      currentSetting.color === toolSetting.color &&
      currentSetting.width === toolSetting.width &&
      currentSetting.opacity === toolSetting.opacity) {
      return;
    }

    session.updateToolSetting(toolSetting);
  }
}
