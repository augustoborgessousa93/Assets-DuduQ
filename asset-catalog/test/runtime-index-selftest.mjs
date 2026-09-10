import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const runtimePath = path.resolve(here, '..', 'runtime-index.js');
const source = fs.readFileSync(runtimePath, 'utf8');

assert.match(source, /DUDUQ CANONICAL ASSET CATALOG — RUNTIME INDEX/);
assert.match(source, /AUTO-GENERATED from asset-catalog\/assets-index\.json/);

const sandbox = {};
vm.createContext(sandbox);
new vm.Script(source, { filename: 'runtime-index.js' }).runInContext(sandbox);

const catalog = sandbox.DUDUQ_CANONICAL_ASSET_CATALOG;
assert.ok(catalog, 'runtime must expose DUDUQ_CANONICAL_ASSET_CATALOG');
assert.equal(Number(catalog.schemaVersion), 2, 'runtime catalog must be schemaVersion 2');
assert.equal(Number(catalog.stats?.unresolvedCollisions || 0), 0);
assert.equal(Number(catalog.stats?.warnings || 0), 0);
assert.equal(Number(catalog.stats?.errors || 0), 0);
assert.ok(Object.isFrozen(catalog), 'catalog must be frozen');
assert.ok(Object.isFrozen(catalog.assets), 'catalog.assets must be frozen');
assert.ok(Object.isFrozen(catalog.aliases), 'catalog.aliases must be frozen');
assert.ok(Object.isFrozen(catalog.byKey), 'catalog.byKey must be frozen');

const descriptor = Object.getOwnPropertyDescriptor(sandbox, 'DUDUQ_CANONICAL_ASSET_CATALOG');
assert.equal(descriptor?.writable, false);
assert.equal(descriptor?.configurable, false);

function normalizeSemanticAssetName(value) {
  let normalized = String(value == null ? '' : value).trim();
  try { normalized = decodeURIComponent(normalized); } catch {}
  normalized = normalized.split(/[?#]/)[0];
  normalized = normalized.slice(normalized.lastIndexOf('/') + 1);
  normalized = normalized.replace(/\.[a-z0-9]{2,5}$/i, '');
  return normalized.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
    .replace(/&/g, ' e ').replace(/[_-]+/g, ' ').replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

function resolveDetails(value) {
  const query = normalizeSemanticAssetName(value);
  if (!query) return null;
  const aliasId = catalog.aliases?.[query];
  const exactId = catalog.byKey?.[query];
  const id = String(aliasId || exactId || '');
  if (!id) return null;
  const asset = catalog.assets?.[id];
  if (!asset) return null;
  return {
    file: String(asset.file || ''),
    strategy: aliasId ? 'ALIAS' : 'KEY',
    id
  };
}

const checks = [
  ['dog', 'animal-dog-cachorro.png'],
  ['children greeting', 'scene-children-greeting.png'],
  ['profile:maya', 'character-maya.png'],
  ['duo:maya:leo', 'y3-duo-leo-maya-context.png'],
  ['green car', 'y3-green-car.png'],
  ['two green eyes', 'y3-two-green-eyes.png'],
  ['20', 'number-20-twenty-vinte.png'],
  ['30', 'number-30-thirty-trinta.png'],
  ['38', 'number-38-thirty-eight-trinta-e-oito.png'],
  ['40', 'number-40-forty-quarenta.png'],
  ['thirty-eight', 'number-38-thirty-eight-trinta-e-oito.png'],
  ['thirty eight', 'number-38-thirty-eight-trinta-e-oito.png'],
  ['trinta e oito', 'number-38-thirty-eight-trinta-e-oito.png']
];

for (const [query, expectedFile] of checks) {
  const result = resolveDetails(query);
  assert.ok(result, `runtime sentinel not resolved: ${query}`);
  assert.equal(result.file, expectedFile, `runtime wrong target for ${query}`);
  assert.ok(result.strategy === 'ALIAS' || result.strategy === 'KEY', `forbidden runtime strategy for ${query}`);
  console.log(`OK: ${query} -> ${result.file} [${result.strategy}]`);
}

assert.equal(resolveDetails('definitely-missing-duduq-asset'), null, 'unknown semantic query must not masquerade as a real asset');
const fallbackId = catalog.fallbacks?.['*'];
assert.ok(fallbackId, 'global fallback id missing');
assert.equal(catalog.assets?.[fallbackId]?.file, 'placeholder-generic-image.svg', 'global fallback must be placeholder-generic-image.svg');

console.log('RUNTIME_INDEX_LOAD = PASS');
console.log('RUNTIME_INDEX_COMPATIBILITY = PASS');
console.log('RUNTIME_SENTINELS = PASS');
console.log('FALLBACK_RUNTIME = PASS');
