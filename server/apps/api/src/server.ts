import { loadEnv } from './config/env.js';
import { buildApp } from './app.js';

async function main() {
  const env = loadEnv();
  const { app, log } = await buildApp(env);
  await app.listen({ host: env.HOST, port: env.PORT });
  log.info({ port: env.PORT }, 'yxz-api listening');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
