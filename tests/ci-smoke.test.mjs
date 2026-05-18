import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reportDir = path.join(rootDir, 'reports', 'tests');

function readJson(relativePath) {
  return JSON.parse(readFileSync(path.join(rootDir, relativePath), 'utf8'));
}

function readText(relativePath) {
  return readFileSync(path.join(rootDir, relativePath), 'utf8');
}

function listSourceFiles(dir) {
  const absoluteDir = path.join(rootDir, dir);
  return readdirSync(absoluteDir, { withFileTypes: true }).flatMap((entry) => {
    const relativePath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      return listSourceFiles(relativePath);
    }
    return /\.(ets|ts)$/.test(entry.name) ? [relativePath] : [];
  });
}

const tests = [
  {
    name: 'app metadata declares a runnable HarmonyOS application',
    run() {
      const app = readJson('AppScope/app.json5').app;

      assert.equal(app.bundleName, 'com.example.hosn');
      assert.equal(app.versionName, '1.0.0');
      assert.ok(Number.isInteger(app.versionCode));
      assert.ok(app.versionCode > 0);
    }
  },
  {
    name: 'entry module exposes EntryAbility for supported devices',
    run() {
      const module = readJson('entry/src/main/module.json5').module;

      assert.equal(module.name, 'entry');
      assert.equal(module.type, 'entry');
      assert.equal(module.mainElement, 'EntryAbility');
      assert.deepEqual(module.deviceTypes, ['phone', 'tablet', '2in1']);
      assert.equal(module.abilities[0].srcEntry, './ets/entryability/EntryAbility.ets');
      assert.ok(existsSync(path.join(rootDir, 'entry/src/main/ets/entryability/EntryAbility.ets')));
    }
  },
  {
    name: 'main page profile references existing pages',
    run() {
      const pages = readJson('entry/src/main/resources/base/profile/main_pages.json').src;

      assert.deepEqual(pages, [
        'pages/Index',
        'features/home/pages/HomePage',
        'features/notebook/pages/NotebookListPage',
        'features/editor/pages/EditorPage'
      ]);

      for (const page of pages) {
        assert.ok(existsSync(path.join(rootDir, 'entry/src/main/ets', `${page}.ets`)), `${page}.ets should exist`);
      }
    }
  },
  {
    name: 'application route map contains core navigation targets',
    run() {
      const routeMap = readText('entry/src/main/ets/app/RouteMap.ts');

      for (const route of ['index', 'home', 'notebookList', 'editor']) {
        assert.match(routeMap, new RegExp(`key: '${route}'`));
      }

      assert.match(routeMap, /DEFAULT_START_ROUTE:\s*string\s*=\s*ROUTE_NAME_MAP\.home/);
    }
  },
  {
    name: 'core source tree contains expected application layers',
    run() {
      const sourceFiles = listSourceFiles('entry/src/main/ets');
      const requiredFiles = [
        'entry/src/main/ets/domain/usecases/CreateNotebook.ts',
        'entry/src/main/ets/domain/usecases/CreateNotebookPage.ts',
        'entry/src/main/ets/domain/repositories/NotebookRepository.ts',
        'entry/src/main/ets/data/repositories/NotebookRepositoryImpl.ts',
        'entry/src/main/ets/features/editor/pages/EditorPage.ets',
        'entry/src/main/ets/features/notebook/viewmodels/NotebookListViewModel.ts'
      ];

      assert.ok(sourceFiles.length >= 50, `expected at least 50 source files, found ${sourceFiles.length}`);
      for (const file of requiredFiles) {
        assert.ok(existsSync(path.join(rootDir, file)), `${file} should exist`);
      }
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

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

mkdirSync(reportDir, { recursive: true });
writeFileSync(
  path.join(reportDir, 'ci-smoke.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<testsuite name="ci-smoke" tests="${results.length}" failures="${failures.length}">`,
    ...results.map((result) => {
      const seconds = (result.time / 1000).toFixed(3);
      const base = `  <testcase classname="ci-smoke" name="${escapeXml(result.name)}" time="${seconds}">`;

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

console.log(`${results.length - failures.length}/${results.length} tests passed`);

if (failures.length > 0) {
  process.exitCode = 1;
}
