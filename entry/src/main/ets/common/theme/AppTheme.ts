export interface AppThemeColorOption {
  id: string;
  label: string;
  color: string;
  softColor: string;
}

export class AppTheme {
  static readonly DEFAULT_COLOR: string = '#2E6BFF';
  static readonly WHITE_COLOR: string = '#FFFFFF';
  static readonly STORAGE_LINK_KEY: string = 'storage.app.theme.color';
  static readonly PALETTE: AppThemeColorOption[] = [
    { id: 'white', label: 'White', color: '#FFFFFF', softColor: '#E8EEFF' },
    { id: 'blue', label: 'Blue', color: '#2E6BFF', softColor: '#E8EEFF' },
    { id: 'indigo', label: 'Indigo', color: '#6366F1', softColor: '#EEF2FF' },
    { id: 'violet', label: 'Violet', color: '#7C3AED', softColor: '#F1E9FF' },
    { id: 'teal', label: 'Teal', color: '#0F9F8F', softColor: '#E6FAF7' },
    { id: 'green', label: 'Green', color: '#16A34A', softColor: '#EAF7EE' },
    { id: 'amber', label: 'Amber', color: '#D97706', softColor: '#FFF4DB' },
    { id: 'rose', label: 'Rose', color: '#E11D48', softColor: '#FFE8EF' }
  ];

  static normalizeThemeColor(color: string): string {
    if (typeof color !== 'string') {
      return AppTheme.DEFAULT_COLOR;
    }

    const normalizedColor: string = color.trim().toUpperCase();
    if (/^#[0-9A-F]{6}$/.test(normalizedColor)) {
      return normalizedColor;
    }
    return AppTheme.DEFAULT_COLOR;
  }

  static isWhiteTheme(color: string): boolean {
    return AppTheme.normalizeThemeColor(color) === AppTheme.WHITE_COLOR;
  }

  static getAccentColor(color: string): string {
    if (AppTheme.isWhiteTheme(color)) {
      return AppTheme.DEFAULT_COLOR;
    }
    return AppTheme.normalizeThemeColor(color);
  }

  static getThemeOptions(): AppThemeColorOption[] {
    const options: AppThemeColorOption[] = [];
    for (const option of AppTheme.PALETTE) {
      options.push({
        id: option.id,
        label: option.label,
        color: option.color,
        softColor: option.softColor
      });
    }
    return options;
  }

  static getSoftColor(color: string): string {
    const normalizedColor: string = AppTheme.normalizeThemeColor(color);
    for (const option of AppTheme.PALETTE) {
      if (option.color === normalizedColor) {
        return option.softColor;
      }
    }
    return '#E8EEFF';
  }

  static getTintColor(color: string, alphaHex: string = '33'): string {
    const normalizedAlpha: string = /^[0-9A-Fa-f]{2}$/.test(alphaHex) ? alphaHex.toUpperCase() : '33';
    const normalizedColor: string = AppTheme.getAccentColor(color);
    return `#${normalizedAlpha}${normalizedColor.slice(1)}`;
  }

  static getShellBackgroundColor(color: string): string {
    if (AppTheme.isWhiteTheme(color)) {
      return '#F3F5FA';
    }
    return AppTheme.mixWithWhite(AppTheme.getAccentColor(color), 0.05);
  }

  static getPanelBackgroundColor(color: string): string {
    if (AppTheme.isWhiteTheme(color)) {
      return '#FAFBFF';
    }
    return AppTheme.mixWithWhite(AppTheme.getAccentColor(color), 0.08);
  }

  static getTopBarBackgroundColor(color: string): string {
    if (AppTheme.isWhiteTheme(color)) {
      return '#FAFBFF';
    }
    return AppTheme.mixColors('#111827', AppTheme.getAccentColor(color), 0.68);
  }

  static getSidebarBackgroundColor(color: string): string {
    if (AppTheme.isWhiteTheme(color)) {
      return '#F8FAFF';
    }
    return AppTheme.mixWithWhite(AppTheme.getAccentColor(color), 0.1);
  }

  static getBorderColor(color: string): string {
    if (AppTheme.isWhiteTheme(color)) {
      return '#D8DEE9';
    }
    return AppTheme.mixColors('#D8DEE9', AppTheme.getAccentColor(color), 0.18);
  }

  static getTopBarTextColor(color: string): string {
    return AppTheme.isWhiteTheme(color) ? '#0F172A' : '#FFFFFF';
  }

  private static mixWithWhite(color: string, ratio: number): string {
    return AppTheme.mixColors('#FFFFFF', AppTheme.normalizeThemeColor(color), ratio);
  }

  private static mixColors(baseColor: string, accentColor: string, ratio: number): string {
    const normalizedBaseColor: string = AppTheme.normalizeThemeColor(baseColor);
    const normalizedAccentColor: string = AppTheme.normalizeThemeColor(accentColor);
    const normalizedRatio: number = AppTheme.clampRatio(ratio);
    const red: number = AppTheme.mixChannel(
      AppTheme.readHexChannel(normalizedBaseColor, 1),
      AppTheme.readHexChannel(normalizedAccentColor, 1),
      normalizedRatio
    );
    const green: number = AppTheme.mixChannel(
      AppTheme.readHexChannel(normalizedBaseColor, 3),
      AppTheme.readHexChannel(normalizedAccentColor, 3),
      normalizedRatio
    );
    const blue: number = AppTheme.mixChannel(
      AppTheme.readHexChannel(normalizedBaseColor, 5),
      AppTheme.readHexChannel(normalizedAccentColor, 5),
      normalizedRatio
    );

    return `#${AppTheme.toHexChannel(red)}${AppTheme.toHexChannel(green)}${AppTheme.toHexChannel(blue)}`;
  }

  private static clampRatio(ratio: number): number {
    if (!Number.isFinite(ratio)) {
      return 0;
    }
    return Math.max(0, Math.min(1, ratio));
  }

  private static mixChannel(baseValue: number, accentValue: number, ratio: number): number {
    return Math.round(baseValue + (accentValue - baseValue) * ratio);
  }

  private static readHexChannel(color: string, startIndex: number): number {
    return Number.parseInt(color.slice(startIndex, startIndex + 2), 16);
  }

  private static toHexChannel(value: number): string {
    return value.toString(16).toUpperCase().padStart(2, '0');
  }
}
