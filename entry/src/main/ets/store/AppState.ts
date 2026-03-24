export interface AppState {
  currentNotebookId?: string;
  currentPageId?: string;
  currentTool: 'pen' | 'eraser';
}

export const initialAppState: AppState = {
  currentTool: 'pen'
};
