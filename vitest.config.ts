import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    reporters: ['default', 'junit'],
    outputFile: {
      junit: 'reports/tests/vitest.xml'
    },
    coverage: {
      provider: 'v8',
      reportsDirectory: 'reports/coverage',
      reporter: ['text', 'html', 'json', 'lcov'],
      include: [
        'entry/src/main/ets/common/utils/ElementBoundsUtil.ts',
        'entry/src/main/ets/common/utils/GeometryUtil.ts',
        'entry/src/main/ets/common/utils/IdUtil.ts',
        'entry/src/main/ets/common/utils/TimeUtil.ts',
        'entry/src/main/ets/domain/entities/Stroke.ts',
        'entry/src/main/ets/domain/entities/ToolSetting.ts',
        'entry/src/main/ets/features/editor/controllers/StrokeSpatialHashIndex.ts'
      ],
      exclude: [
        '**/*.ets',
        '**/node_modules/**',
        '**/oh_modules/**',
        '**/build/**'
      ],
      thresholds: {
        lines: 85,
        functions: 85,
        branches: 75,
        statements: 85
      }
    }
  }
});
