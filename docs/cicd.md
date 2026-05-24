# CI/CD Pipeline

This project uses Jenkins Pipeline to build, test, package, and archive a HarmonyOS application.

## What The Pipeline Runs

| Stage | Purpose |
| --- | --- |
| `Clean Reports` | Removes reports from the previous build. |
| `Environment` | Verifies DevEco Studio, HarmonyOS SDK, OHPM, Node, npm, Hvigor, and Java. |
| `Static Project Checks` | Checks that required project, CI, lockfile, and `ohosTest` files exist. |
| `Install Node Test Dependencies` | Runs `npm ci` from the committed `package-lock.json`. |
| `TypeScript Typecheck` | Runs `tsc -p tsconfig.ci.json` for pure TypeScript logic. |
| `Quality Gate` | Verifies CI files, ignore rules, coverage thresholds, and official HarmonyOS test hooks. |
| `Smoke Tests` | Runs repository structure and app metadata smoke tests. |
| `HarmonyOS Test Config Check` | Verifies `entry/src/ohosTest`, Hypium, and Jenkins official device-test switches are wired. |
| `Vitest Coverage` | Runs Vitest with V8 coverage for pure TypeScript domain/controller utilities. |
| `Install OHPM Dependencies` | Runs `ohpm install --all` only when OHPM dependencies or devDependencies are declared. |
| `Build Unsigned HAP` | Runs Hvigor to compile ArkTS/ETS and package a HAP. |
| `Package Check` | Verifies a non-empty unsigned HAP exists. |
| `Device Smoke` | Optional `hdc` device or emulator connectivity check. |
| `HarmonyOS Device Tests` | Optional official `hvigor onDeviceTest` run for `ohosTest` and Hypium tests. |
| `HarmonyOS Runtime Coverage` | Optional official `hvigor collectCoverage` run after device tests. |

The pipeline archives JUnit XML reports, Vitest coverage, HAP artifacts, HarmonyOS coverage outputs, and Hvigor build logs.

## Required Jenkins Configuration

Prefer setting these values as Jenkins global environment variables or build parameters instead of committing local paths:

| Variable | Meaning |
| --- | --- |
| `DEVECO_HOME` or `DEVECO_HOME_OVERRIDE` | DevEco Studio installation directory. |
| `DEVECO_SDK_HOME` or `DEVECO_SDK_HOME_OVERRIDE` | HarmonyOS SDK directory. Defaults to `DEVECO_HOME/sdk`. |
| `JAVA_HOME` or `JAVA_HOME_OVERRIDE` | JDK used by Hvigor and Jenkins. |
| `REPO_DIR` | Optional. Leave empty when Jenkins checks out this repository into `WORKSPACE`. Set it only for a local Jenkins job that runs against an existing working copy. |

The committed `Jenkinsfile` does not contain local Windows paths such as `F:\...` or `C:\Users\...`.

## Host-Side Checks

Host-side checks run without a device or emulator:

- `npm run test:typecheck` checks pure TypeScript files that can be compiled outside DevEco.
- `npm run test:quality` protects CI structure, ignore rules, coverage thresholds, and official HarmonyOS test hooks.
- `npm run test:smoke` checks HarmonyOS metadata, routes, pages, and important source-tree layout.
- `npm run test:ohos` checks the official `ohosTest` structure, Hypium dependency, and Jenkins device-test stages.
- `npm run test:coverage` generates V8 coverage for pure TypeScript logic under `reports/coverage`.
- Hvigor compiles ArkTS/ETS and packages the application into an unsigned HAP.

## Official HarmonyOS Device Tests

HarmonyOS runtime tests are configured under `entry/src/ohosTest`:

- `entry/src/ohosTest/module.json5` declares the test module and `TestAbility`.
- `entry/src/ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets` implements the official TestKit runner.
- `entry/src/ohosTest/ets/testability/TestAbility.ets` starts Hypium through `Hypium.hypiumTest`.
- `entry/src/ohosTest/ets/test/List.test.ets` collects device test suites.
- `@ohos/hypium` is declared as an OHPM dev dependency and locked in `oh-package-lock.json5`.

To run device tests in Jenkins, attach a HarmonyOS emulator or device so `hdc list targets` returns a target, then build with:

- `RUN_HARMONYOS_DEVICE_TESTS=true`
- `COLLECT_HARMONYOS_COVERAGE=true`

Jenkins then runs:

```text
hvigor onDeviceTest --no-daemon --no-incremental --no-type-check
hvigor collectCoverage --no-daemon --no-type-check
```

Device tests are disabled by default because a CI node without a connected device would otherwise fail before the host-side build, reports, and HAP packaging can complete.

## Current Signing Constraint

The current local DevEco debug signing certificate has expired. The pipeline allows a signing failure only when an unsigned HAP is still produced, controlled by `ALLOW_UNSIGNED_HAP=true`.

For a stricter release pipeline, configure fresh signing material through DevEco or Jenkins Credentials and set `ALLOW_UNSIGNED_HAP=false`. Do not commit `.p12`, `.p7b`, `.cer`, `.jks`, or keystore files.

## CI Requirement Coverage

The required CI/CD items are covered as follows:

- Compile source code: Hvigor build compiles ArkTS/ETS and TypeScript typecheck compiles host-testable TS.
- Run tests: smoke tests, quality gate tests, Vitest unit tests, and optional official HarmonyOS Hypium device tests.
- Package runnable artifact: Hvigor generates an unsigned `.hap`, then package checks verify it exists and is non-empty.
- Feedback/logs: Jenkins console output, JUnit XML reports, coverage reports, archived HAPs, and Hvigor logs.
- Trigger on commits: `pollSCM('H/5 * * * *')` lets Jenkins detect main-branch changes when the job is configured with SCM.
