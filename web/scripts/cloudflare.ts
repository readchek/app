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
const app = [
  "default-src 'self'",
  "connect-src https:",
  "img-src 'self' blob:",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ")

// The book reader's frame shows a publication's own pages. It runs in a
// sandbox of its own origin, takes the book's styles, images and fonts as
// blob URLs, runs only the reader's scripts, and reaches nothing on the
// network. Only this app may frame it.
const frame = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'unsafe-inline' blob:",
  "img-src blob: data:",
  "font-src blob: data:",
  "media-src blob:",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'self'",
].join("; ")

await Bun.write(
  resolve(dist, "_headers"),
  `/assets/*
  Cache-Control: public, max-age=31536000, immutable

/*
  Content-Security-Policy: ${app}
  X-Frame-Options: DENY
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff

/reader-frame/*
  ! Content-Security-Policy
  ! X-Frame-Options
  Content-Security-Policy: ${frame}
`,
)

await cleanBuildOutputDir(root)
await writeRootConfig(root, { accountId: config.accountId }, { isPreview: false, mode: undefined })
await writeWorkerConfig({ root, config: config.worker })
await writeAssets({ root, sourceDirectory: dist })
