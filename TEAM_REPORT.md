# Part II. Team Report

## 1. Metrics

### 总览

| Metric | Value |
| --- | ---: |
| Lines of Code | 33,234 |
| Number of source files | 94 |
| Number of functions / methods | 1,892 |
| Total cyclomatic complexity | 5,853 |
| Average CC per function | 3.09 |
| Median CC per function | 2 |
| Max function CC | 68 |
| Functions with CC > 10 | 51 |
| Functions with CC > 20 | 6 |

### 复杂度热点 Top 10

| Function | File | Line | CC |
| --- | --- | ---: | ---: |
| `handleTouch` | `CanvasBoard.ets` | 1377 | 68 |
| `build` | `NotebookListPanel.ets` | 4703 | 28 |
| `buildWorkspace` | `EditorPage.ets` | 659 | 26 |
| `isOcrTextContainerKey` | `XfyunOcrService.ts` | 576 | 23 |
| `handleStrokeResizeTouch` | `CanvasBoard.ets` | 1874 | 22 |
| `handleLassoTouch` | `CanvasBoard.ets` | 1681 | 21 |
| `describeOcrPayloadShape` | `XfyunOcrService.ts` | 644 | 18 |
| `parseNotebookExportPageRange` | `EditorPage.ets` | 4047 | 17 |
| `handleDocumentSurfaceTouch` | `EditorPage.ets` | 3185 | 15 |
| `updateActivePageCanvasSize` | `EditorPage.ets` | 4448 | 15 |

### 文件热点 Top 5

| File | LOC | CC |
| --- | ---: | ---: |
| `CanvasBoard.ets` | 5,423 | 785 |
| `EditorPage.ets` | 4,346 | 614 |
| `NotebookListPanel.ets` | 4,908 | 546 |
| `DrawingEditorViewModel.ts` | 4,412 | 519 |
| `XfyunOcrService.ts` | 911 | 208 |

### 依赖

| 包管理器 | 依赖 | 类型 | 数量 |
| --- | --- | --- | ---: |
| npm (`package.json`) | `@types/node`, `@vitest/coverage-v8`, `typescript`, `vitest` | devDependencies | 4 |
| ohpm (`oh-package.json5`) | `@ohos/hypium` | devDependencies | 1 |
| **合计** | | | **5** |

---

## 2. CI/CD Pipeline Description

### 概述

项目使用 **Jenkins Declarative Pipeline**，配置文件为仓库根目录的 `Jenkinsfile`。每 5 分钟轮询 SCM。支持 Windows / Linux 双平台。

**Pipeline 配置入口**：[`Jenkinsfile`](https://github.com/sustech-cs304/team-project-26spring-26s-3/blob/main/Jenkinsfile)

### Pipeline 阶段

| # | 阶段 | 工具 / 技术 | 说明 |
| ---: | --- | --- | --- |
| 1 | Clean Reports | shell | 清理 `reports/` 和 `.ci-cache/tmp` |
| 2 | Environment | Hvigor, OHPM, Node.js, JDK | 验证 DevEco SDK 工具链可用性 |
| 3 | Static Project Checks | shell | 检查 `module.json5`、`build-profile.json5`、锁文件等关键文件存在 |
| 4 | Install Node Test Dependencies | `npm ci` | 安装 Vitest、TypeScript 等 Node 测试依赖 |
| 5 | TypeScript Typecheck | `tsc -p tsconfig.ci.json` | `.ts` 源文件类型检查 |
| 6 | Quality Gate | `tests/ci-quality-gate.mjs` | CI 配置完整性检查（无本地路径、锁文件存在、gitignore 正确等） |
| 7 | Project Metrics | `tests/ci-metrics.mjs` | AST 级解析生成 LOC、圈复杂度、依赖数 |
| 8 | SCC Metrics (可选) | `scc` | 第三方工具交叉验证 LOC/CC |
| 9 | PMD CPD (可选) | PMD CPD | 重复代码检测 |
| 10 | Smoke Tests | `tests/ci-smoke.test.mjs` | 冒烟测试：验证 module.json5、页面注册、路由、源码结构 |
| 11 | HarmonyOS Test Config Check | `tests/ci-ohos-test-check.mjs` | 验证 ohosTest 配置和 Hypium 依赖 |
| 12 | Vitest Coverage | `vitest run --coverage` | 单元测试 + `@vitest/coverage-v8` 覆盖率 |
| 13 | Install OHPM Dependencies | `ohpm install --all` | 安装鸿蒙侧测试依赖 |
| 14 | Build Unsigned HAP | Hvigor `assembleApp` | 构建未签名 HAP |
| 15 | Package Check | `tests/ci-package-check.mjs` | 验证 HAP 产物存在 |
| 16 | Device Smoke | `hdc` | 检测连接的真机 / 模拟器 |
| 17 | HarmonyOS Device Tests | Hvigor `onDeviceTest` | 真机运行 Hypium 测试 |
| 18 | HarmonyOS Runtime Coverage | Hvigor `collectCoverage` | 鸿蒙端运行时覆盖率 |

### 技术栈总览

| 类别 | 工具 |
| --- | --- |
| CI 平台 | Jenkins |
| 构建系统 | Hvigor (HarmonyOS 官方) |
| 包管理 | npm + OHPM |
| 类型检查 | TypeScript 5.6 |
| 单元测试 / 覆盖率 | Vitest 2.1 + `@vitest/coverage-v8` |
| 设备测试 | Hypium (`@ohos/hypium`) + hdc |
| 指标计算 | `tests/ci-metrics.mjs`（自研 AST 解析）+ scc / PMD CPD（可选交叉验证） |
| 产物管理 | JUnit XML 报告 + 构建产物归档 |

### 流水线配置清单

| 文件 | 用途 |
| --- | --- |
| `Jenkinsfile` | Pipeline 主配置 |
| `tests/ci-smoke.test.mjs` | 冒烟测试 |
| `tests/ci-quality-gate.mjs` | 质量门 |
| `tests/ci-metrics.mjs` | 指标自动计算 |
| `tests/ci-ohos-test-check.mjs` | 鸿蒙测试配置检查 |
| `tests/ci-ohpm-deps.mjs` | OHPM 依赖检查 |
| `tests/ci-package-check.mjs` | 构建产物验证 |
| `tests/ci-scc-report.mjs` | scc 交叉验证 |
| `tests/ci-pmd-cpd.mjs` | PMD CPD 重复代码检测 |
| `vitest.config.ts` | Vitest 配置 |
| `tsconfig.ci.json` | CI TypeScript 配置 |

### 流水线执行成功证据

#### Smoke Tests — 5/5 通过

```
testsuite name="ci-smoke" tests="5" failures="0"
  ✓ app metadata declares a runnable HarmonyOS application
  ✓ entry module exposes EntryAbility for supported devices
  ✓ main page profile references existing pages
  ✓ application route map contains core navigation targets
  ✓ core source tree contains expected application layers
```

#### Quality Gate — 5/5 通过

```
testsuite name="quality-gate" tests="5" failures="0"
  ✓ committable CI files do not contain local absolute paths
  ✓ dependency lockfile and CI scripts are present
  ✓ generated reports and sensitive signing files are ignored
  ✓ coverage thresholds remain enabled
  ✓ official HarmonyOS test and coverage gates are configured
```

#### ohosTest Config Check — 5/5 通过

```
testsuite name="ohos-test-check" tests="5" failures="0"
  ✓ ohosTest target is declared for official HarmonyOS test builds
  ✓ Hypium is locked as an OHPM dev dependency
  ✓ ohosTest module exposes a test ability
  ✓ official Hypium runner is wired to the test suite
  ✓ Jenkins exposes official device test and runtime coverage gates
```

#### Vitest — 26/26 通过

```
testsuites name="vitest tests" tests="26" failures="0"
  domain-geometry.test.ts ......... 9/9
  domain-utils.test.ts ............ 9/9
  editor-controllers.test.ts ...... 8/8
```

#### Package Check — 1/1 通过

```
testsuite name="package-check" tests="1" failures="0"
  ✓ unsigned HAP is produced
```
