import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const reportDir = join(rootDir, 'reports', 'metrics');
const testReportDir = join(rootDir, 'reports', 'tests');
const sccBin = process.env.SCC_BIN || 'scc';

function runScc(args, outputPath) {
  const result = spawnSync(sccBin, args, {
    cwd: rootDir,
    encoding: 'utf8'
  });

  if (result.error) {
    throw new Error(`Unable to run scc. Install scc or set SCC_BIN. ${result.error.message}`);
  }

  if (result.status !== 0) {
    throw new Error(`scc failed with exit code ${result.status}.\n${result.stderr || result.stdout}`);
  }

  if (outputPath && result.stdout.trim().length > 0) {
    writeFileSync(outputPath, result.stdout);
  }

  return result;
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

mkdirSync(reportDir, { recursive: true });
mkdirSync(testReportDir, { recursive: true });

runScc([
  '--include-ext',
  'ets,ts',
  '--exclude-dir',
  'build,node_modules,oh_modules,.hvigor,.preview,.test',
  '--by-file',
  '--format',
  'json',
  'entry/src/main/ets'
], join(reportDir, 'scc.json'));

runScc([
  '--include-ext',
  'ets,ts',
  '--exclude-dir',
  'build,node_modules,oh_modules,.hvigor,.preview,.test',
  '--by-file',
  '--format',
  'html',
  'entry/src/main/ets'
], join(reportDir, 'scc.html'));

writeFileSync(
  join(testReportDir, 'scc.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<testsuite name="scc-metrics" tests="1" failures="0">',
    `  <testcase classname="scc-metrics" name="${escapeXml('scc metrics generated')}" time="0.000"></testcase>`,
    '</testsuite>',
    ''
  ].join('\n')
);

console.log('scc reports generated: reports/metrics/scc.json, reports/metrics/scc.html');
