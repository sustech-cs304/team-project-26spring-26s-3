import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reportDir = path.join(rootDir, 'reports', 'tests');

function walkFiles(relativeDir) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!existsSync(absoluteDir)) {
    return [];
  }

  return readdirSync(absoluteDir, { withFileTypes: true }).flatMap((entry) => {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      return walkFiles(relativePath);
    }
    return [relativePath];
  });
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

const startedAt = performance.now();
let failure = null;

try {
  const packages = [
    ...walkFiles('build/outputs'),
    ...walkFiles('entry/build')
  ].filter((file) => /\.(app|hap|zip)$/i.test(file));

  const unsignedHaps = packages.filter((file) => /-unsigned\.hap$/i.test(file));
  assert.ok(unsignedHaps.length > 0, 'expected at least one unsigned HAP under entry/build');

  for (const file of packages) {
    const absolutePath = path.join(rootDir, file);
    const size = statSync(absolutePath).size;
    assert.ok(size > 0, `${file} should not be empty`);
    console.log(`${file} ${size} bytes`);
  }
} catch (error) {
  failure = error;
  console.error(error.stack || error.message);
}

mkdirSync(reportDir, { recursive: true });
const seconds = ((performance.now() - startedAt) / 1000).toFixed(3);
const testcase = failure
  ? [
      `  <testcase classname="package-check" name="unsigned HAP is produced" time="${seconds}">`,
      `    <failure message="${escapeXml(failure.message)}">${escapeXml(failure.stack || failure.message)}</failure>`,
      '  </testcase>'
    ].join('\n')
  : `  <testcase classname="package-check" name="unsigned HAP is produced" time="${seconds}"></testcase>`;

writeFileSync(
  path.join(reportDir, 'package-check.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<testsuite name="package-check" tests="1" failures="${failure ? 1 : 0}">`,
    testcase,
    '</testsuite>',
    ''
  ].join('\n')
);

if (failure) {
  process.exitCode = 1;
}
