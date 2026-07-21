/**
 * Writes src/environments/environment.ts from the API_URL environment variable.
 *
 * Angular bundles the frontend ahead of time, so API_URL is resolved at BUILD
 * time, not at container start. It must therefore point at an address the
 * end user's browser can reach (a public host or IP), never at an internal
 * Compose service name such as http://backend:8000.
 */
const fs = require('fs');
const path = require('path');

// Load .env if present. Absent file is fine - real environments (CI, Docker
// build args) provide the variables directly.
require('dotenv').config();

const DEFAULT_API_URL = 'http://localhost:8000/api';
const apiUrl = process.env.API_URL || DEFAULT_API_URL;

const targetPath = path.join(__dirname, '..', 'src', 'environments', 'environment.ts');

const contents = `// GENERATED FILE - do not edit by hand.
//
// This file is rewritten by \`scripts/set-env.js\`, which runs automatically
// before \`npm start\` and \`npm run build\`. The value below is the local
// development default; the container build overrides it via API_URL.
export const environment = {
  apiUrl: '${apiUrl}',
};
`;

fs.mkdirSync(path.dirname(targetPath), { recursive: true });
fs.writeFileSync(targetPath, contents, { encoding: 'utf8' });

if (!process.env.API_URL) {
  console.log(`[set-env] API_URL not set, falling back to ${DEFAULT_API_URL}`);
} else {
  console.log(`[set-env] apiUrl set to ${apiUrl}`);
}
