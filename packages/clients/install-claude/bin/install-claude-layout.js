#!/usr/bin/env node
import { runCli } from '@rbx/repo-layout-cli';

const exitCode = await runCli(process.argv.slice(2), { presetClient: 'claude' });
process.exitCode = exitCode;