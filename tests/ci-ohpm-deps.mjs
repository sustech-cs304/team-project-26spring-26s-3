import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifests = ['oh-package.json5', 'entry/oh-package.json5'];

function hasDeclaredDependency(relativePath) {
  const absolutePath = path.join(rootDir, relativePath);
  if (!existsSync(absolutePath)) {
    return false;
  }

  const content = readFileSync(absolutePath, 'utf8');
  return /"(?:dependencies|devDependencies)"\s*:\s*\{[^}]*"[^"]+"\s*:/.test(content);
}

const needsInstall = manifests.some(hasDeclaredDependency);
console.log(needsInstall ? 'OHPM dependencies detected.' : 'No OHPM dependencies declared.');
process.exitCode = needsInstall ? 0 : 1;
