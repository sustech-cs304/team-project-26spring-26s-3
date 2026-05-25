import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reportDir = path.join(rootDir, 'reports', 'tests');

function readText(relativePath) {
  return readFileSync(path.join(rootDir, relativePath), 'utf8');
}

function readJson(relativePath) {
  return JSON.parse(readText(relativePath));
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

const tests = [
  {
    name: 'committable CI files do not contain local absolute paths',
    run() {
      const files = ['Jenkinsfile', 'package.json', 'tsconfig.ci.json', 'vitest.config.ts'];
      const forbiddenPatterns = [
        /\b[A-Z]:\\(?:Users|hoson|deveco|ProgramData)\\/i,
        /\/Users\/[^/\s]+/,
        /\/Applications\/DevEco-Studio\.app/,
        /C:\\ProgramData\\Jenkins/i
      ];

      for (const file of files) {
        const content = readText(file);
        for (const pattern of forbiddenPatterns) {
          assert.equal(pattern.test(content), false, `${file} contains local-only path pattern ${pattern}`);
        }
      }
    }
  },
  {
    name: 'dependency lockfile and CI scripts are present',
    run() {
      const packageJson = readJson('package.json');

      assert.ok(existsSync(path.join(rootDir, 'package-lock.json')), 'package-lock.json should be committed for npm ci');
      assert.ok(existsSync(path.join(rootDir, 'tsconfig.ci.json')), 'tsconfig.ci.json should be committed for CI typecheck');
      assert.equal(packageJson.scripts['test:typecheck'], 'tsc -p tsconfig.ci.json');
      assert.match(packageJson.scripts['test:ci'], /test:typecheck/);
      assert.equal(packageJson.scripts['test:smoke'], 'node tests/ci-smoke.test.mjs');
      assert.equal(packageJson.scripts['test:quality'], 'node tests/ci-quality-gate.mjs');
      assert.equal(packageJson.scripts['test:ohos'], 'node tests/ci-ohos-test-check.mjs');
      assert.equal(packageJson.scripts.metrics, 'node tests/ci-metrics.mjs');
      assert.equal(packageJson.scripts['metrics:scc'], 'node tests/ci-scc-report.mjs');
      assert.equal(packageJson.scripts['quality:cpd'], 'node tests/ci-pmd-cpd.mjs');
      assert.equal(packageJson.scripts['test:coverage'], 'vitest run --coverage');
      assert.match(packageJson.scripts['test:ci'], /test:ohos/);
      assert.match(packageJson.scripts['test:ci'], /metrics/);
    }
  },
  {
    name: 'generated reports and sensitive signing files are ignored',
    run() {
      const gitignore = readText('.gitignore');

      for (const expected of ['reports/', 'node_modules/', 'oh_modules/', '**/build/', '*.p12', '*.jks', '*.keystore']) {
        assert.match(gitignore, new RegExp(expected.replaceAll('*', '\\*').replaceAll('/', '\\/')));
      }
    }
  },
  {
    name: 'coverage thresholds remain enabled',
    run() {
      const config = readText('vitest.config.ts');

      assert.match(config, /thresholds\s*:\s*\{/);
      assert.match(config, /lines\s*:\s*85/);
      assert.match(config, /statements\s*:\s*85/);
      assert.match(config, /branches\s*:\s*75/);
      assert.match(config, /functions\s*:\s*85/);
    }
  },
  {
    name: 'official HarmonyOS test and coverage gates are configured',
    run() {
      const jenkinsfile = readText('Jenkinsfile');

      assert.match(jenkinsfile, /RUN_HARMONYOS_DEVICE_TESTS/);
      assert.match(jenkinsfile, /COLLECT_HARMONYOS_COVERAGE/);
      assert.match(jenkinsfile, /onDeviceTest/);
      assert.match(jenkinsfile, /collectCoverage/);
      assert.match(jenkinsfile, /Project Metrics/);
      assert.match(jenkinsfile, /SCC Metrics/);
      assert.match(jenkinsfile, /PMD CPD/);
      assert.match(jenkinsfile, /RUN_SCC_METRICS/);
      assert.match(jenkinsfile, /RUN_PMD_CPD/);
      assert.match(jenkinsfile, /reports\/metrics\/\*\*/);
      assert.match(jenkinsfile, /reports\/pmd\/\*\*/);
      assert.match(jenkinsfile, /WORKSPACE/);
      assert.ok(existsSync(path.join(rootDir, 'entry/src/ohosTest/module.json5')), 'ohosTest module should exist');
      assert.ok(existsSync(path.join(rootDir, 'tests/ci-ohpm-deps.mjs')), 'OHPM dependency detector should exist');
      assert.ok(existsSync(path.join(rootDir, 'tests/ci-metrics.mjs')), 'project metrics script should exist');
      assert.ok(existsSync(path.join(rootDir, 'tests/ci-scc-report.mjs')), 'scc report script should exist');
      assert.ok(existsSync(path.join(rootDir, 'tests/ci-pmd-cpd.mjs')), 'PMD CPD report script should exist');
    }
  }
];

const results = [];

for (const test of tests) {
  const startedAt = performance.now();
  try {
    test.run();
    results.push({ name: test.name, time: performance.now() - startedAt });
    console.log(`PASS ${test.name}`);
  } catch (error) {
    results.push({ name: test.name, time: performance.now() - startedAt, error });
    console.error(`FAIL ${test.name}`);
    console.error(error.stack || error.message);
  }
}

const failures = results.filter((result) => result.error);

mkdirSync(reportDir, { recursive: true });
writeFileSync(
  path.join(reportDir, 'quality-gate.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<testsuite name="quality-gate" tests="${results.length}" failures="${failures.length}">`,
    ...results.map((result) => {
      const seconds = (result.time / 1000).toFixed(3);
      const base = `  <testcase classname="quality-gate" name="${escapeXml(result.name)}" time="${seconds}">`;

      if (!result.error) {
        return `${base}</testcase>`;
      }

      return [
        base,
        `    <failure message="${escapeXml(result.error.message)}">${escapeXml(result.error.stack || result.error.message)}</failure>`,
        '  </testcase>'
      ].join('\n');
    }),
    '</testsuite>',
    ''
  ].join('\n')
);

console.log(`${results.length - failures.length}/${results.length} quality checks passed`);

if (failures.length > 0) {
  process.exitCode = 1;
}
