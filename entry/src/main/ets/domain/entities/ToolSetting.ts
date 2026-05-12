export const TOOL_TYPES = ['pen', 'pencil', 'highlighter', 'eraser', 'text', 'shape', 'edit'] as const;
export const DRAWABLE_TOOL_TYPES = ['pen', 'pencil', 'highlighter'] as const;

export type ToolType = typeof TOOL_TYPES[number];
export type DrawableToolType = typeof DRAWABLE_TOOL_TYPES[number];

export function isToolType(value: string): value is ToolType {
  return TOOL_TYPES.includes(value as ToolType);
}

export function isDrawableToolType(value: string): value is DrawableToolType {
  return DRAWABLE_TOOL_TYPES.includes(value as DrawableToolType);
}

export interface ToolSetting {
  tool: ToolType;
  color: string;
  width: number;
  opacity: number;
}
