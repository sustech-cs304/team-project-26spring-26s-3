import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const reportDir = join(rootDir, 'reports', 'pmd');
const testReportDir = join(rootDir, 'reports', 'tests');
const pmdBin = process.env.PMD_BIN || 'pmd';
const minimumTokens = process.env.PMD_CPD_MINIMUM_TOKENS || '80';

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function runPmd(args, outputPath) {
  const useJavaLauncher = process.platform === 'win32' && pmdBin.toLowerCase().endsWith('.bat');
  const pmdHome = useJavaLauncher ? resolve(dirname(pmdBin), '..') : '';
  const pmdClasspath = useJavaLauncher
    ? [join(pmdHome, 'conf'), join(pmdHome, 'lib', '*')].join(process.platform === 'win32' ? ';' : ':')
    : '';
  const command = useJavaLauncher
    ? 'java'
    : pmdBin;
  const commandArgs = useJavaLauncher
    ? ['-cp', pmdClasspath, 'net.sourceforge.pmd.cli.PmdCli', ...args]
    : args;
  const result = spawnSync(command, commandArgs, {
    cwd: rootDir,
    encoding: 'utf8'
  });

  if (result.error) {
    throw new Error(`Unable to run PMD CPD. Install PMD or set PMD_BIN. ${result.error.message}`);
  }

  if (outputPath) {
    writeFileSync(outputPath, result.stdout || '');
  }

  if (result.status !== 0) {
    throw new Error(`PMD CPD failed with exit code ${result.status}.\n${result.stderr || result.stdout}`);
  }
}

mkdirSync(reportDir, { recursive: true });
mkdirSync(testReportDir, { recursive: true });

runPmd([
  'cpd',
  '--dir',
  'entry/src/main/ets',
  '--language',
  'typescript',
  '--minimum-tokens',
  minimumTokens,
  '--format',
  'xml',
  '--no-fail-on-violation'
], join(reportDir, 'cpd.xml'));

runPmd([
  'cpd',
  '--dir',
  'entry/src/main/ets',
  '--language',
  'typescript',
  '--minimum-tokens',
  minimumTokens,
  '--format',
  'text',
  '--no-fail-on-violation'
], join(reportDir, 'cpd.txt'));

writeFileSync(
  join(testReportDir, 'pmd-cpd.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<testsuite name="pmd-cpd" tests="1" failures="0">',
    `  <testcase classname="pmd-cpd" name="${escapeXml('PMD CPD duplicate-code report generated')}" time="0.000"></testcase>`,
    '</testsuite>',
    ''
  ].join('\n')
);

console.log(`PMD CPD reports generated with minimum tokens=${minimumTokens}: reports/pmd/cpd.xml, reports/pmd/cpd.txt`);
