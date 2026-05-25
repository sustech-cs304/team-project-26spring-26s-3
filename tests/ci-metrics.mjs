import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reportDir = path.join(rootDir, 'reports', 'metrics');
const testReportDir = path.join(rootDir, 'reports', 'tests');
const sourceRoots = ['entry/src/main/ets'];
const sourceExtensions = new Set(['.ets', '.ts']);
const ignoredSegments = new Set([
  '.git',
  '.hvigor',
  '.preview',
  '.test',
  'build',
  'node_modules',
  'oh_modules'
]);

const decisionKeywordPattern = /\b(if|for|while|case|catch)\b/g;
const logicalOperatorPattern = /&&|\|\|/g;
const functionHeaderPattern = /^(?:(?:private|public|protected|static|readonly)\s+)*(?:async\s+)?([a-z_$][\w$]*)\s*\(/s;
const functionKeywordPattern = /^function\s+([a-zA-Z_$][\w$]*)\s*\(/s;
const ignoredFunctionNames = new Set(['if', 'for', 'while', 'switch', 'catch']);

function toPosixPath(filePath) {
  return path.relative(rootDir, filePath).replaceAll(path.sep, '/');
}

function walkSourceFiles(relativeDir) {
  const dir = path.join(rootDir, relativeDir);

  if (!existsSync(dir)) {
    return [];
  }

  const files = [];
  const entries = readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    if (ignoredSegments.has(entry.name)) {
      continue;
    }

    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      files.push(...walkSourceFiles(path.relative(rootDir, fullPath)));
      continue;
    }

    if (entry.isFile() && sourceExtensions.has(path.extname(entry.name))) {
      files.push(fullPath);
    }
  }

  return files.sort((left, right) => toPosixPath(left).localeCompare(toPosixPath(right)));
}

function stripCommentsAndStrings(source) {
  let output = '';
  let state = 'code';
  let quote = '';

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1] ?? '';

    if (state === 'lineComment') {
      if (char === '\n') {
        output += '\n';
        state = 'code';
      }
      continue;
    }

    if (state === 'blockComment') {
      if (char === '\n') {
        output += '\n';
      }
      if (char === '*' && next === '/') {
        index += 1;
        state = 'code';
      }
      continue;
    }

    if (state === 'string') {
      if (char === '\\') {
        index += 1;
        continue;
      }
      if (char === '\n') {
        output += '\n';
        continue;
      }
      if (char === quote) {
        output += ' ';
        state = 'code';
      }
      continue;
    }

    if (char === '/' && next === '/') {
      state = 'lineComment';
      index += 1;
      continue;
    }

    if (char === '/' && next === '*') {
      state = 'blockComment';
      index += 1;
      continue;
    }

    if (char === '"' || char === "'" || char === '`') {
      state = 'string';
      quote = char;
      output += ' ';
      continue;
    }

    output += char;
  }

  return output;
}

function countMatches(text, pattern) {
  return [...text.matchAll(pattern)].length;
}

function countTernaryOperators(text) {
  let count = 0;

  for (let index = 0; index < text.length; index += 1) {
    if (text[index] !== '?') {
      continue;
    }

    const previous = text[index - 1] ?? '';
    const next = text[index + 1] ?? '';
    const nextNonWhitespace = text.slice(index + 1).match(/\S/)?.[0] ?? '';

    if (previous === '?' || next === '?' || next === '.' || nextNonWhitespace === ':') {
      continue;
    }

    count += 1;
  }

  return count;
}

function countLogicalLoc(cleanedSource) {
  return cleanedSource
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .length;
}

function getLineOffsets(source) {
  const offsets = [0];

  for (let index = 0; index < source.length; index += 1) {
    if (source[index] === '\n') {
      offsets.push(index + 1);
    }
  }

  return offsets;
}

function getLineNumber(lineOffsets, offset) {
  let low = 0;
  let high = lineOffsets.length - 1;

  while (low <= high) {
    const middle = Math.floor((low + high) / 2);

    if (lineOffsets[middle] <= offset) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }

  return high + 1;
}

function findMatchingBrace(source, openBraceIndex) {
  let depth = 0;

  for (let index = openBraceIndex; index < source.length; index += 1) {
    if (source[index] === '{') {
      depth += 1;
      continue;
    }

    if (source[index] !== '}') {
      continue;
    }

    depth -= 1;

    if (depth === 0) {
      return index;
    }
  }

  return -1;
}

function resolveFunctionName(signature) {
  const trimmedSignature = signature.trim();
  const functionKeywordMatch = trimmedSignature.match(functionKeywordPattern);

  if (functionKeywordMatch) {
    return functionKeywordMatch[1];
  }

  const methodMatch = trimmedSignature.match(functionHeaderPattern);

  if (!methodMatch) {
    return '';
  }

  return methodMatch[1];
}

function isFunctionSignatureStart(line) {
  const trimmedLine = line.trim();

  if (trimmedLine.length === 0 || trimmedLine.startsWith('//') || trimmedLine.startsWith('*')) {
    return false;
  }

  if (trimmedLine.startsWith('function ')) {
    return true;
  }

  const name = resolveFunctionName(trimmedLine);

  if (!name || ignoredFunctionNames.has(name)) {
    return false;
  }

  return name[0] === name[0].toLowerCase();
}

function getLineIndexForOffset(lineOffsets, offset) {
  return getLineNumber(lineOffsets, offset) - 1;
}

function extractFunctionMetrics(filePath, cleanedSource) {
  const lines = cleanedSource.split(/\r?\n/);
  const lineOffsets = getLineOffsets(cleanedSource);
  const functions = [];

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    const leadingWhitespace = line.length - line.trimStart().length;

    if (!isFunctionSignatureStart(line)) {
      continue;
    }

    const startOffset = lineOffsets[lineIndex] + leadingWhitespace;
    const openBraceIndex = cleanedSource.indexOf('{', startOffset);

    if (openBraceIndex === -1) {
      continue;
    }

    const semicolonIndex = cleanedSource.indexOf(';', startOffset);

    if (semicolonIndex !== -1 && semicolonIndex < openBraceIndex) {
      continue;
    }

    const signature = cleanedSource.slice(startOffset, openBraceIndex);
    const name = resolveFunctionName(signature);

    if (!name || ignoredFunctionNames.has(name)) {
      continue;
    }

    const closeBraceIndex = findMatchingBrace(cleanedSource, openBraceIndex);

    if (closeBraceIndex === -1) {
      continue;
    }

    const body = cleanedSource.slice(openBraceIndex + 1, closeBraceIndex);
    const keywordDecisions = countMatches(body, decisionKeywordPattern);
    const logicalDecisions = countMatches(body, logicalOperatorPattern);
    const ternaryDecisions = countTernaryOperators(body);
    const decisionPoints = keywordDecisions + logicalDecisions + ternaryDecisions;
    const lineNumber = getLineNumber(lineOffsets, startOffset);

    functions.push({
      name,
      path: toPosixPath(filePath),
      line: lineNumber,
      loc: countLogicalLoc(`${signature}\n${body}`),
      cyclomaticComplexity: decisionPoints + 1,
      decisionPoints,
      decisions: {
        keywords: keywordDecisions,
        logicalOperators: logicalDecisions,
        ternaryOperators: ternaryDecisions
      }
    });

    lineIndex = getLineIndexForOffset(lineOffsets, closeBraceIndex);
  }

  return functions;
}

function calculateFileMetrics(filePath) {
  const source = readFileSync(filePath, 'utf8');
  const cleaned = stripCommentsAndStrings(source);
  const keywordDecisions = countMatches(cleaned, decisionKeywordPattern);
  const logicalDecisions = countMatches(cleaned, logicalOperatorPattern);
  const ternaryDecisions = countTernaryOperators(cleaned);
  const decisionPoints = keywordDecisions + logicalDecisions + ternaryDecisions;
  const functions = extractFunctionMetrics(filePath, cleaned);

  return {
    path: toPosixPath(filePath),
    loc: countLogicalLoc(cleaned),
    cyclomaticComplexity: decisionPoints + 1,
    decisionPoints,
    functions: functions.length,
    decisions: {
      keywords: keywordDecisions,
      logicalOperators: logicalDecisions,
      ternaryOperators: ternaryDecisions
    },
    functionMetrics: functions
  };
}

function stripJsonComments(text) {
  let output = '';
  let state = 'code';
  let quote = '';

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1] ?? '';

    if (state === 'lineComment') {
      if (char === '\n') {
        output += '\n';
        state = 'code';
      }
      continue;
    }

    if (state === 'blockComment') {
      if (char === '\n') {
        output += '\n';
      }
      if (char === '*' && next === '/') {
        index += 1;
        state = 'code';
      }
      continue;
    }

    if (state === 'string') {
      output += char;

      if (char === '\\') {
        index += 1;
        output += text[index] ?? '';
        continue;
      }

      if (char === quote) {
        state = 'code';
      }
      continue;
    }

    if (char === '/' && next === '/') {
      state = 'lineComment';
      index += 1;
      continue;
    }

    if (char === '/' && next === '*') {
      state = 'blockComment';
      index += 1;
      continue;
    }

    if (char === '"' || char === "'") {
      state = 'string';
      quote = char;
    }

    output += char;
  }

  return output.replace(/,\s*([}\]])/g, '$1').trim();
}

function readJsonLike(relativePath) {
  const fullPath = path.join(rootDir, relativePath);

  if (!existsSync(fullPath)) {
    return null;
  }

  return JSON.parse(stripJsonComments(readFileSync(fullPath, 'utf8')));
}

function getDependencySummary() {
  const files = ['package.json', 'oh-package.json5', 'entry/oh-package.json5'];
  const categories = ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies'];
  const byFile = [];
  const uniqueDirectDependencies = new Set();
  let directReferences = 0;
  let runtimeDependencies = 0;
  let developmentDependencies = 0;

  for (const file of files) {
    const manifest = readJsonLike(file);

    if (!manifest) {
      continue;
    }

    const fileSummary = { file, categories: {}, total: 0 };

    for (const category of categories) {
      const dependencies = manifest[category] ?? {};
      const names = Object.keys(dependencies).sort();

      if (names.length === 0) {
        continue;
      }

      fileSummary.categories[category] = names;
      fileSummary.total += names.length;
      directReferences += names.length;

      if (category === 'dependencies') {
        runtimeDependencies += names.length;
      } else {
        developmentDependencies += names.length;
      }

      for (const name of names) {
        uniqueDirectDependencies.add(`${category}:${name}`);
      }
    }

    byFile.push(fileSummary);
  }

  return {
    directReferences,
    uniqueDirectDependencies: uniqueDirectDependencies.size,
    runtimeDependencies,
    developmentDependencies,
    manifests: byFile
  };
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function formatMarkdown(metrics) {
  const topFunctions = metrics.functions
    .slice()
    .sort((left, right) => right.cyclomaticComplexity - left.cyclomaticComplexity || right.loc - left.loc)
    .slice(0, 10);
  const topFiles = metrics.files
    .slice()
    .sort((left, right) => right.cyclomaticComplexity - left.cyclomaticComplexity || right.loc - left.loc)
    .slice(0, 5);

  const dependencyLines = metrics.dependencies.manifests.flatMap((manifest) => {
    const lines = [`### ${manifest.file}`];
    const categories = Object.entries(manifest.categories);

    if (categories.length === 0) {
      lines.push('- No direct dependencies declared.');
      return lines;
    }

    for (const [category, names] of categories) {
      lines.push(`- ${category}: ${names.length} (${names.join(', ')})`);
    }

    return lines;
  });

  return [
    '# Project Metrics',
    '',
    'Generated by `npm run metrics`.',
    '',
    '## Scope',
    '',
    `- Source roots: ${metrics.scope.sourceRoots.join(', ')}`,
    `- Source extensions: ${metrics.scope.sourceExtensions.join(', ')}`,
    '- Generated folders, dependency folders, build outputs, comments, and blank lines are excluded from LOC.',
    '- Cyclomatic complexity is computed as `1 + decision points` per function or method. Decision points include `if`, `for`, `while`, `case`, `catch`, ternary `?`, `&&`, and `||` after comments and string literals are stripped.',
    '- Inline callback logic is attributed to the containing method so the report remains compatible with ArkTS/ETS UI DSL syntax.',
    '',
    '## Summary',
    '',
    '| Metric | Value |',
    '| --- | ---: |',
    `| Lines of Code | ${metrics.summary.linesOfCode} |`,
    `| Number of source files | ${metrics.summary.sourceFiles} |`,
    `| Number of measured functions/methods | ${metrics.summary.functions} |`,
    `| Total function cyclomatic complexity | ${metrics.summary.totalFunctionCyclomaticComplexity} |`,
    `| Average cyclomatic complexity per function | ${metrics.summary.averageCyclomaticComplexityPerFunction} |`,
    `| Median cyclomatic complexity per function | ${metrics.summary.medianCyclomaticComplexityPerFunction} |`,
    `| Max function cyclomatic complexity | ${metrics.summary.maxFunctionCyclomaticComplexity} |`,
    `| Functions with complexity > 10 | ${metrics.summary.functionsOver10} |`,
    `| Functions with complexity > 20 | ${metrics.summary.functionsOver20} |`,
    `| Direct dependency references | ${metrics.dependencies.directReferences} |`,
    `| Unique direct dependencies by category | ${metrics.dependencies.uniqueDirectDependencies} |`,
    `| Runtime dependencies | ${metrics.dependencies.runtimeDependencies} |`,
    `| Development dependencies | ${metrics.dependencies.developmentDependencies} |`,
    '',
    '## Highest Complexity Functions',
    '',
    '| Function | File | Line | LOC | Cyclomatic complexity | Decision points |',
    '| --- | --- | ---: | ---: | ---: | ---: |',
    ...topFunctions.map((fn) => `| ${fn.name} | ${fn.path} | ${fn.line} | ${fn.loc} | ${fn.cyclomaticComplexity} | ${fn.decisionPoints} |`),
    '',
    '## File Hotspots',
    '',
    '| File | LOC | Cyclomatic complexity | Decision points |',
    '| --- | ---: | ---: | ---: |',
    ...topFiles.map((file) => `| ${file.path} | ${file.loc} | ${file.cyclomaticComplexity} | ${file.decisionPoints} |`),
    '',
    '## Dependencies',
    '',
    ...dependencyLines,
    ''
  ].join('\n');
}

const sourceFiles = sourceRoots.flatMap(walkSourceFiles);
const files = sourceFiles.map(calculateFileMetrics);
const functions = files.flatMap((file) => file.functionMetrics);
const linesOfCode = files.reduce((sum, file) => sum + file.loc, 0);
const totalFunctionCyclomaticComplexity = functions.reduce((sum, fn) => sum + fn.cyclomaticComplexity, 0);
const sortedFunctionComplexities = functions
  .map((fn) => fn.cyclomaticComplexity)
  .sort((left, right) => left - right);
const maxFunctionCyclomaticComplexity = sortedFunctionComplexities.at(-1) ?? 0;
const averageCyclomaticComplexityPerFunction = functions.length === 0
  ? 0
  : Number((totalFunctionCyclomaticComplexity / functions.length).toFixed(2));
const medianCyclomaticComplexityPerFunction = sortedFunctionComplexities.length === 0
  ? 0
  : sortedFunctionComplexities.length % 2 === 1
    ? sortedFunctionComplexities[(sortedFunctionComplexities.length - 1) / 2]
    : Number(((
        sortedFunctionComplexities[sortedFunctionComplexities.length / 2 - 1] +
        sortedFunctionComplexities[sortedFunctionComplexities.length / 2]
      ) / 2).toFixed(2));
const functionsOver10 = functions.filter((fn) => fn.cyclomaticComplexity > 10).length;
const functionsOver20 = functions.filter((fn) => fn.cyclomaticComplexity > 20).length;
const maxFileCyclomaticComplexity = files.reduce(
  (max, file) => Math.max(max, file.cyclomaticComplexity),
  0
);

assert.ok(files.length > 0, 'Expected at least one source file to measure.');
assert.ok(linesOfCode > 0, 'Expected measured source files to contain code.');
assert.ok(functions.length > 0, 'Expected at least one function or method to measure.');

const metrics = {
  generatedAt: new Date().toISOString(),
  scope: {
    sourceRoots,
    sourceExtensions: [...sourceExtensions].sort()
  },
  summary: {
    linesOfCode,
    sourceFiles: files.length,
    functions: functions.length,
    totalFunctionCyclomaticComplexity,
    averageCyclomaticComplexityPerFunction,
    medianCyclomaticComplexityPerFunction,
    maxFunctionCyclomaticComplexity,
    functionsOver10,
    functionsOver20,
    maxFileCyclomaticComplexity
  },
  dependencies: getDependencySummary(),
  files: files.map(({ functionMetrics, ...file }) => file),
  functions
};

mkdirSync(reportDir, { recursive: true });
mkdirSync(testReportDir, { recursive: true });

writeFileSync(path.join(reportDir, 'project-metrics.json'), `${JSON.stringify(metrics, null, 2)}\n`);
writeFileSync(path.join(reportDir, 'project-metrics.md'), formatMarkdown(metrics));
writeFileSync(
  path.join(testReportDir, 'metrics.xml'),
  [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<testsuite name="project-metrics" tests="1" failures="0">',
    `  <testcase classname="project-metrics" name="${escapeXml('project metrics generated')}" time="0.000"></testcase>`,
    '</testsuite>',
    ''
  ].join('\n')
);

console.log('Project metrics generated:');
console.log(`  Lines of Code: ${metrics.summary.linesOfCode}`);
console.log(`  Source files: ${metrics.summary.sourceFiles}`);
console.log(`  Functions/methods: ${metrics.summary.functions}`);
console.log(`  Total function cyclomatic complexity: ${metrics.summary.totalFunctionCyclomaticComplexity}`);
console.log(`  Average cyclomatic complexity per function: ${metrics.summary.averageCyclomaticComplexityPerFunction}`);
console.log(`  Max function cyclomatic complexity: ${metrics.summary.maxFunctionCyclomaticComplexity}`);
console.log(`  Direct dependency references: ${metrics.dependencies.directReferences}`);
console.log(`  Report: ${path.relative(rootDir, path.join(reportDir, 'project-metrics.md'))}`);
