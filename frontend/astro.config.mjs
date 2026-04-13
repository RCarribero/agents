import tailwind from '@astrojs/tailwind';
import { defineConfig } from 'astro/config';

export default defineConfig({
  integrations: [tailwind()],
  server: { host: '127.0.0.1', port: 3011 },
  vite: {
    ssr: {
      external: ['better-sqlite3'],
    },
  },
});
