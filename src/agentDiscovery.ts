import { promises as fs } from 'node:fs';
import path from 'node:path';

/**
 * Discovers all available agents by scanning the agents/ directory for *.agent.md files.
 * Excludes memoria_global.md and other non-agent markdown files.
 */
export async function discoverAgentCatalog(agentsDir: string): Promise<string[]> {
  try {
    const entries = await fs.readdir(agentsDir, { withFileTypes: true });
    const agents = entries
      .filter((entry) => entry.isFile() && entry.name.endsWith('.agent.md'))
      .map((entry) => entry.name.replace(/\.agent\.md$/, ''))
      .sort();
    return agents;
  } catch (error) {
    return [];
  }
}
