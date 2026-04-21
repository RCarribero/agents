#!/usr/bin/env node
import { runCli } from '@rbx/repo-layout-cli';

const exitCode = await runCli(process.argv.slice(2), { presetClient: 'copilot' });
process.exitCode = exitCode;