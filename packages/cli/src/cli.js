import {
  buildInstallPlan,
  getCleanupPolicy,
  listSupportedClients,
  resolveSupportedClient,
} from './install-planner.js';

const VALID_MODES = new Set(['global', 'repo', 'both']);

const HELP_TEXT = `repo-layout-install

Usage:
  repo-layout-install plan --client <name> [--mode global|repo|both] [--json]
  repo-layout-install resolve --client <name> [--json]
  repo-layout-install clients [--json]
  repo-layout-install cleanup-policy [--json]

Clients:
  claude, codex, copilot, cursor, antigravity, windsurf
`;

function isFlag(token) {
  return typeof token === 'string' && /^-{1,2}\S+/.test(token);
}

function parseArgs(argv) {
  const args = {
    command: 'plan',
    client: null,
    mode: 'both',
    modeProvided: false,
    json: false,
    help: false,
  };
  const positional = [];

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === '--client') {
      args.client = argv[index + 1] ?? null;
      index += 1;
      continue;
    }

    if (token.startsWith('--client=')) {
      args.client = token.slice('--client='.length);
      continue;
    }

    if (token === '--mode') {
      args.mode = argv[index + 1] ?? null;
      args.modeProvided = true;
      index += 1;
      continue;
    }

    if (token.startsWith('--mode=')) {
      args.mode = token.slice('--mode='.length);
      args.modeProvided = true;
      continue;
    }

    if (token === '--json') {
      args.json = true;
      continue;
    }

    if (token === '-h' || token === '--help') {
      args.help = true;
      continue;
    }

    if (isFlag(token)) {
      throw new Error(`Unknown flag "${token}".`);
    }

    positional.push(token);
  }

  if (positional.length > 0) {
    args.command = positional[0];
  }

  return args;
}

function validateMode(mode) {
  if (typeof mode !== 'string' || !VALID_MODES.has(mode)) {
    throw new Error('Invalid mode. Expected one of: global, repo, both.');
  }
}

function filterPlanByMode(plan, mode) {
  if (mode === 'global') {
    return { ...plan, repo: [] };
  }

  if (mode === 'repo') {
    return { ...plan, global: [] };
  }

  return plan;
}

function printHuman(value) {
  if (Array.isArray(value)) {
    for (const entry of value) {
      console.log(String(entry));
    }
    return;
  }

  if (value && typeof value === 'object') {
    console.log(JSON.stringify(value, null, 2));
    return;
  }

  console.log(String(value));
}

export async function runCli(argv = process.argv.slice(2), options = {}) {
  const args = parseArgs(argv);
  const presetClient = options.presetClient ?? null;

  if (presetClient && args.client && args.client !== presetClient) {
    console.error(`Wrapper locked to client \"${presetClient}\".`);
    return 1;
  }

  if (presetClient && !args.client) {
    args.client = presetClient;
  }

  if (args.help) {
    console.log(HELP_TEXT);
    return 0;
  }

  try {
    if (args.modeProvided || args.command === 'plan') {
      validateMode(args.mode);
    }

    let output;

    switch (args.command) {
      case 'clients':
        output = listSupportedClients();
        break;
      case 'cleanup-policy':
        output = await getCleanupPolicy();
        break;
      case 'resolve':
        output = await resolveSupportedClient(args.client);
        break;
      case 'plan':
        output = filterPlanByMode(await buildInstallPlan({ client: args.client }), args.mode);
        break;
      default:
        console.error(`Unknown command \"${args.command}\".`);
        return 1;
    }

    if (args.json) {
      console.log(JSON.stringify(output, null, 2));
    } else {
      printHuman(output);
    }

    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}