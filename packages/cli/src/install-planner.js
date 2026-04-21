const SUPPORTED_CLIENTS = Object.freeze([
  'claude',
  'codex',
  'copilot',
  'cursor',
  'antigravity',
  'windsurf',
]);

const LEGACY_WRAPPERS = Object.freeze([
  'scripts/install-copilot-layout/install-copilot-layout.sh',
  'scripts/install-copilot-layout/install-copilot-layout.ps1',
  'scripts/install-repo-layout/install-repo-layout.sh',
  'scripts/install-repo-layout/install-repo-layout.ps1',
  'scripts/start/start.sh',
  'scripts/start/start.ps1',
]);

const CLIENTS = Object.freeze({
  claude: {
    name: 'claude',
    displayName: 'Claude',
    packages: {
      cli: '@rbx/repo-layout-cli',
      wrapper: '@rbx/install-claude-layout',
    },
    targets: {
      global: [
        {
          id: 'claude-global-commands',
          kind: 'conventional',
          path: '~/.claude/commands',
          env: 'CLAUDE_HOME',
          description: 'Global Claude command snippets and install helpers.',
        },
      ],
      repo: [
        {
          id: 'claude-repo-commands',
          kind: 'conventional',
          path: '.claude/commands',
          description: 'Repository-local Claude command set.',
        },
      ],
    },
  },
  codex: {
    name: 'codex',
    displayName: 'Codex',
    packages: {
      cli: '@rbx/repo-layout-cli',
      wrapper: '@rbx/install-codex-layout',
    },
    targets: {
      global: [
        {
          id: 'codex-global-prompts',
          kind: 'conventional',
          path: '~/.codex/prompts',
          env: 'CODEX_HOME',
          description: 'Global Codex prompt and layout assets.',
        },
      ],
      repo: [
        {
          id: 'codex-repo-prompts',
          kind: 'conventional',
          path: '.codex/prompts',
          description: 'Repository-local Codex prompt bundle.',
        },
      ],
    },
  },
  copilot: {
    name: 'copilot',
    displayName: 'GitHub Copilot',
    packages: {
      cli: '@rbx/repo-layout-cli',
      wrapper: '@rbx/install-copilot-layout',
    },
    legacy: {
      wrappers: LEGACY_WRAPPERS,
    },
    targets: {
      global: [
        {
          id: 'copilot-global-prompts',
          kind: 'detected',
          env: 'VSCODE_USER_PROMPTS_FOLDER',
          candidates: [
            '%APPDATA%/Code - Insiders/User/prompts',
            '%APPDATA%/Code/User/prompts',
            '~/.config/Code - Insiders/User/prompts',
            '~/.config/Code/User/prompts'
          ],
          description: 'VS Code user prompts plus shared Copilot toolkit files.',
        },
      ],
      repo: [
        {
          id: 'copilot-repo-github',
          kind: 'repo',
          path: '.github/',
          description: 'Copilot instructions, prompts, workflows, and repo scripts.',
        },
      ],
    },
  },
  cursor: {
    name: 'cursor',
    displayName: 'Cursor',
    packages: {
      cli: '@rbx/repo-layout-cli',
      wrapper: '@rbx/install-cursor-layout',
    },
    targets: {
      global: [
        {
          id: 'cursor-global-rules',
          kind: 'conventional',
          path: '~/.cursor/rules',
          env: 'CURSOR_HOME',
          description: 'Global Cursor rules and shared templates.',
        },
      ],
      repo: [
        {
          id: 'cursor-repo-rules',
          kind: 'conventional',
          path: '.cursor/rules',
          description: 'Repository-local Cursor rule bundle.',
        },
      ],
    },
  },
  antigravity: {
    name: 'antigravity',
    displayName: 'Antigravity',
    packages: {
      cli: '@rbx/repo-layout-cli',
      wrapper: '@rbx/install-antigravity-layout',
    },
    notes: [
      'Docs unresolved. Install path must be supplied explicitly.',
    ],
    targets: {
      global: [
        {
          id: 'antigravity-global-config',
          kind: 'configurable',
          env: 'ANTIGRAVITY_CONFIG_DIR',
          path: null,
          description: 'User-supplied Antigravity global config dir.',
        },
      ],
      repo: [
        {
          id: 'antigravity-repo-config',
          kind: 'configurable',
          env: 'ANTIGRAVITY_REPO_DIR',
          path: null,
          description: 'User-supplied Antigravity repo target dir.',
        },
      ],
    },
  },
  windsurf: {
    name: 'windsurf',
    displayName: 'Windsurf',
    packages: {
      cli: '@rbx/repo-layout-cli',
      wrapper: '@rbx/install-windsurf-layout',
    },
    targets: {
      global: [
        {
          id: 'windsurf-global-rules',
          kind: 'conventional',
          path: '~/.windsurf/rules',
          env: 'WINDSURF_HOME',
          description: 'Global Windsurf rules and shared templates.',
        },
      ],
      repo: [
        {
          id: 'windsurf-repo-rules',
          kind: 'conventional',
          path: '.windsurf/rules',
          description: 'Repository-local Windsurf rule bundle.',
        },
      ],
    },
  },
});

const CLEANUP_POLICY = Object.freeze({
  keep: [
    'legacy wrappers in scripts/install-copilot-layout/**',
    'legacy wrappers in scripts/install-repo-layout/**',
    'scripts/start/** bootstrap wrappers',
    'agents/** contracts and eval assets',
    'config.json skill-installer/autoskills ownership; preserve while toolkit is active',
    'session_log.md append-only audit trail',
  ],
  remove: [
    'command-history-state.json',
    'eval-results.json',
    'package-lock.json',
    'installed-plugins/ when empty',
    'restart/ when empty',
    'runs/ when empty',
    'session-state/ when empty',
    'dist/ generated output',
    'node_modules/ generated dependencies',
  ],
  review: [
    'config.json may point to skills_dir and other live local settings; remove only on explicit reset',
    'logs/ contains runtime evidence; trim only with retention decision',
    'ide/ contains live lock files; do not remove while session active',
  ],
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function normalizeClientName(client) {
  return String(client ?? '').trim().toLowerCase();
}

function ensureClient(client) {
  const normalized = normalizeClientName(client);

  if (!normalized || !CLIENTS[normalized]) {
    throw new Error(
      `Unknown client \"${client}\". Supported clients: ${SUPPORTED_CLIENTS.join(', ')}.`,
    );
  }

  return normalized;
}

function buildScopeSteps(clientConfig, scope) {
  return clientConfig.targets[scope].map((target, index) => ({
    id: `${clientConfig.name}-${scope}-${index + 1}`,
    scope,
    description: target.description,
    target,
    commands: {
      pnpm: `pnpm dlx ${clientConfig.packages.wrapper} --mode ${scope}`,
      npm: `npm exec ${clientConfig.packages.wrapper}@latest -- --mode ${scope}`,
    },
  }));
}

export function listSupportedClients() {
  return [...SUPPORTED_CLIENTS];
}

export async function resolveSupportedClient(client) {
  const normalized = ensureClient(client);
  return clone(CLIENTS[normalized]);
}

export async function buildInstallPlan(options = {}) {
  const resolved = await resolveSupportedClient(options.client);

  return {
    client: resolved.name,
    displayName: resolved.displayName,
    packages: resolved.packages,
    legacy: resolved.legacy ?? null,
    notes: resolved.notes ?? [],
    global: buildScopeSteps(resolved, 'global'),
    repo: buildScopeSteps(resolved, 'repo'),
  };
}

export async function getCleanupPolicy() {
  return clone(CLEANUP_POLICY);
}