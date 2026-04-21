import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = process.cwd();
const SUPPORTED_CLIENTS = [
  'claude',
  'codex',
  'copilot',
  'cursor',
  'antigravity',
  'windsurf',
];

const MODULE_CANDIDATES = [
  path.join(ROOT, 'packages', 'core', 'src', 'install-planner.js'),
  path.join(ROOT, 'packages', 'core', 'src', 'install-planner.mjs'),
  path.join(ROOT, 'packages', 'core', 'src', 'install-planner.cjs'),
  path.join(ROOT, 'packages', 'core', 'src', 'index.js'),
  path.join(ROOT, 'packages', 'core', 'src', 'index.mjs'),
  path.join(ROOT, 'packages', 'core', 'src', 'index.cjs'),
];

async function loadPlannerModule() {
  const modulePath = MODULE_CANDIDATES.find((candidate) => existsSync(candidate));

  assert.ok(
    modulePath,
    [
      'Missing install planner module.',
      'Expected one of:',
      ...MODULE_CANDIDATES.map((candidate) => `- ${path.relative(ROOT, candidate)}`),
    ].join('\n'),
  );

  const imported = await import(pathToFileURL(modulePath).href);
  return imported.default ?? imported;
}

function readJson(relativePath) {
  const filePath = path.join(ROOT, relativePath);
  assert.ok(existsSync(filePath), `Missing required file: ${relativePath}`);
  return JSON.parse(readFileSync(filePath, 'utf8'));
}

function readText(relativePath) {
  const filePath = path.join(ROOT, relativePath);
  assert.ok(existsSync(filePath), `Missing required file: ${relativePath}`);
  return readFileSync(filePath, 'utf8');
}

function getWrapperPackagePaths() {
  return SUPPORTED_CLIENTS.map((client) => path.join('packages', 'clients', `install-${client}`));
}

test('resolveSupportedClient -> targets for all supported clients', async () => {
  const planner = await loadPlannerModule();

  assert.equal(typeof planner.resolveSupportedClient, 'function');

  for (const client of SUPPORTED_CLIENTS) {
    const resolved = await planner.resolveSupportedClient(client);

    assert.equal(resolved.name, client);
    assert.ok(resolved.targets, `Missing targets for ${client}`);
    assert.ok(Array.isArray(resolved.targets.global), `Missing global targets for ${client}`);
    assert.ok(Array.isArray(resolved.targets.repo), `Missing repo targets for ${client}`);
    assert.ok(resolved.targets.global.length > 0, `Expected global target for ${client}`);
    assert.ok(resolved.targets.repo.length > 0, `Expected repo target for ${client}`);
  }
});

test('resolveSupportedClient -> reject unknown client', async () => {
  const planner = await loadPlannerModule();

  assert.equal(typeof planner.resolveSupportedClient, 'function');

  await assert.rejects(
    () => planner.resolveSupportedClient('unknown-client'),
    /unknown client|unsupported client|invalid client/i,
  );
});

test('buildInstallPlan -> global + repo steps per client', async () => {
  const planner = await loadPlannerModule();

  assert.equal(typeof planner.buildInstallPlan, 'function');

  for (const client of SUPPORTED_CLIENTS) {
    const plan = await planner.buildInstallPlan({ client });

    assert.equal(plan.client, client);
    assert.ok(Array.isArray(plan.global), `Missing global plan for ${client}`);
    assert.ok(Array.isArray(plan.repo), `Missing repo plan for ${client}`);
    assert.ok(plan.global.length > 0, `Expected global plan steps for ${client}`);
    assert.ok(plan.repo.length > 0, `Expected repo plan steps for ${client}`);
  }
});

test('workspace metadata -> npm/pnpm packages + bin contract', () => {
  const rootPackage = readJson('package.json');
  const corePackage = readJson(path.join('packages', 'core', 'package.json'));
  const cliPackage = readJson(path.join('packages', 'cli', 'package.json'));
  const cliSource = readText(path.join('packages', 'cli', 'src', 'cli.js'));
  const workspace = readText('pnpm-workspace.yaml');

  assert.match(rootPackage.packageManager ?? '', /^pnpm@/i);
  assert.ok(Array.isArray(rootPackage.workspaces), 'Root workspaces array required');
  assert.ok(rootPackage.workspaces.length > 0, 'Root workspaces cannot be empty');
  assert.ok(rootPackage.workspaces.some((entry) => entry.startsWith('packages/')));
  assert.equal(typeof rootPackage.scripts?.test, 'string');
  assert.equal(typeof rootPackage.scripts?.build, 'string');

  assert.equal(typeof cliPackage.name, 'string');
  assert.ok(cliPackage.name.length > 0, 'CLI package name required');
  assert.equal(typeof cliPackage.bin, 'object');
  assert.ok(Object.keys(cliPackage.bin).length > 0, 'CLI bin entry required');
  assert.deepEqual(corePackage.files, ['src']);
  assert.deepEqual(cliPackage.files, ['bin', 'src']);
  assert.equal(cliPackage.exports?.['.'], './src/cli.js');
  assert.match(cliSource, /from '\.\/install-planner\.js'/);

  assert.match(workspace, /packages:\s*/i);
  assert.match(workspace, /['"]?packages\/(clients|\*)/i);
  assert.match(workspace, /['"]?packages\/core/i);
  assert.match(workspace, /['"]?packages\/cli/i);
});

test('published package graph -> wrappers depend on cli and avoid monorepo-relative imports', () => {
  for (const wrapperPath of getWrapperPackagePaths()) {
    const wrapperPackage = readJson(path.join(wrapperPath, 'package.json'));
    const [binRelativePath] = Object.values(wrapperPackage.bin);
    const binSource = readText(path.join(wrapperPath, binRelativePath));

    assert.deepEqual(wrapperPackage.files, ['bin']);
    assert.equal(wrapperPackage.dependencies?.['@rbx/repo-layout-cli'], '0.1.0');
    assert.doesNotMatch(binSource, /\.\.\.\/|\.\.\//, 'Wrapper bin must not import workspace siblings');
    assert.match(binSource, /@rbx\/repo-layout-cli/);
  }
});

test('cleanup policy -> keep/remove lists for install repo hygiene', async () => {
  const planner = await loadPlannerModule();

  assert.equal(typeof planner.getCleanupPolicy, 'function');

  const cleanupPolicy = await planner.getCleanupPolicy();

  assert.ok(Array.isArray(cleanupPolicy.keep), 'Cleanup keep list required');
  assert.ok(Array.isArray(cleanupPolicy.remove), 'Cleanup remove list required');
  assert.ok(Array.isArray(cleanupPolicy.review), 'Cleanup review list required');
  assert.ok(cleanupPolicy.keep.length > 0, 'Cleanup keep list cannot be empty');
  assert.ok(cleanupPolicy.remove.length > 0, 'Cleanup remove list cannot be empty');
  assert.ok(cleanupPolicy.keep.some((entry) => /legacy|wrapper|scripts\//i.test(entry)));
  assert.ok(cleanupPolicy.keep.some((entry) => /config\.json/i.test(entry)));
  assert.ok(cleanupPolicy.review.some((entry) => /config\.json/i.test(entry)));
  assert.ok(!cleanupPolicy.remove.some((entry) => /config\.json/i.test(entry)));
});

test('cli -> invalid mode fails closed', () => {
  const cliBin = path.join(ROOT, 'packages', 'cli', 'bin', 'repo-layout-install.js');
  const result = spawnSync(process.execPath, [cliBin, 'plan', '--client', 'copilot', '--mode', 'invalid'], {
    cwd: ROOT,
    encoding: 'utf8',
  });

  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /invalid mode/i);
});

test('cli -> unknown flag fails closed', () => {
  const cliBin = path.join(ROOT, 'packages', 'cli', 'bin', 'repo-layout-install.js');
  const result = spawnSync(process.execPath, [cliBin, 'plan', '--client', 'copilot', '--bogus'], {
    cwd: ROOT,
    encoding: 'utf8',
  });

  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /unknown flag/i);
  assert.match(output, /--bogus/);
});

test('cli -> typo flag fails closed', () => {
  const cliBin = path.join(ROOT, 'packages', 'cli', 'bin', 'repo-layout-install.js');
  const result = spawnSync(process.execPath, [cliBin, 'plan', '--client', 'copilot', '--mdoe', 'repo'], {
    cwd: ROOT,
    encoding: 'utf8',
  });

  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /unknown flag/i);
  assert.match(output, /--mdoe/);
});

test('README -> published npm/pnpm usage documented', () => {
  const readme = readText('README.md');

  assert.match(readme, /corepack pnpm/i);
  assert.match(readme, /pnpm dlx @rbx\/repo-layout-cli/i);
  assert.match(readme, /npm exec @rbx\/repo-layout-cli@latest/i);
  assert.match(readme, /npm exec @rbx\/install-copilot-layout@latest/i);
  assert.match(readme, /config\.json/i);
  assert.match(readme, /acepta solo/i);
});