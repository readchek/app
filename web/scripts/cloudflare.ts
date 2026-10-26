// Prepares Vite's build in dist/ for `cf deploy --prebuilt`, as static
// assets only: no server code is deployed.
import { resolve } from "node:path"
import {
  cleanBuildOutputDir,
  writeAssets,
  writeRootConfig,
  writeWorkerConfig,
} from "@cloudflare/build-output-utils"
import config from "../cloudflare.config.ts"

const root = resolve(import.meta.dir, "..")
const dist = resolve(root, "dist")

// Vite names scripts and styles by their content, so they never change.
await Bun.write(
  resolve(dist, "_headers"),
  "/assets/*\n  Cache-Control: public, max-age=31536000, immutable\n\n/*\n  Content-Security-Policy: default-src 'self'; connect-src https:; img-src 'self' blob:; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\n  X-Frame-Options: DENY\n  Referrer-Policy: no-referrer\n  X-Content-Type-Options: nosniff\n",
)

await cleanBuildOutputDir(root)
await writeRootConfig(root, { accountId: config.accountId }, { isPreview: false, mode: undefined })
await writeWorkerConfig({ root, config: config.worker })
await writeAssets({ root, sourceDirectory: dist })
