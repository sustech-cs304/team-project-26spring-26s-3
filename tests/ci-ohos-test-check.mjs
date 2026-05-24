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
    name: 'ohosTest target is declared for official HarmonyOS test builds',
    run() {
      const profile = readJson('entry/build-profile.json5');
      const targetNames = profile.targets.map((target) => target.name);

      assert.ok(targetNames.includes('default'), 'default target should remain declared');
      assert.ok(targetNames.includes('ohosTest'), 'ohosTest target should be declared');
    }
  },
  {
    name: 'Hypium is locked as an OHPM dev dependency',
    run() {
      const manifest = readJson('oh-package.json5');
      const lockfile = readText('oh-package-lock.json5');

      assert.equal(manifest.devDependencies['@ohos/hypium'], '1.0.25');
      assert.match(lockfile, /@ohos\/hypium@1\.0\.25/);
    }
  },
  {
    name: 'ohosTest module exposes a test ability',
    run() {
      const moduleJson = readJson('entry/src/ohosTest/module.json5').module;

      assert.equal(moduleJson.name, 'entry_test');
      assert.equal(moduleJson.type, 'feature');
      assert.equal(moduleJson.mainElement, 'TestAbility');
      assert.ok(existsSync(path.join(rootDir, 'entry/src/ohosTest/ets/testability/TestAbility.ets')));
      assert.ok(existsSync(path.join(rootDir, 'entry/src/ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets')));
    }
  },
  {
    name: 'official Hypium runner is wired to the test suite',
    run() {
      const runner = readText('entry/src/ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets');
      const ability = readText('entry/src/ohosTest/ets/testability/TestAbility.ets');
      const suite = readText('entry/src/ohosTest/ets/test/List.test.ets');

      assert.match(runner, /implements\s+TestRunner/);
      assert.match(runner, /abilityDelegatorRegistry\.getAbilityDelegator/);
      assert.match(ability, /Hypium\.hypiumTest/);
      assert.match(ability, /testsuite/);
      assert.match(suite, /abilityTest\(\)/);
    }
  },
  {
    name: 'Jenkins exposes official device test and runtime coverage gates',
    run() {
      const jenkinsfile = readText('Jenkinsfile');

      assert.match(jenkinsfile, /RUN_HARMONYOS_DEVICE_TESTS/);
      assert.match(jenkinsfile, /COLLECT_HARMONYOS_COVERAGE/);
      assert.match(jenkinsfile, /onDeviceTest/);
      assert.match(jenkinsfile, /collectCoverage/);
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
  path.join(reportDir, 'ohos-test-check.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<testsuite name="ohos-test-check" tests="${results.length}" failures="${failures.length}">`,
    ...results.map((result) => {
      const seconds = (result.time / 1000).toFixed(3);
      const base = `  <testcase classname="ohos-test-check" name="${escapeXml(result.name)}" time="${seconds}">`;

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

console.log(`${results.length - failures.length}/${results.length} ohosTest checks passed`);

if (failures.length > 0) {
  process.exitCode = 1;
}
