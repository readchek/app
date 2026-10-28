// Downloads the demo's library snapshot pinned in demo-snapshot.json from
// assets.chek.page into demo-data/, for the demo build. Every part and the
// whole archive are checked against their SHA-256 first.
//
//   bun scripts/demo-data.ts
import { createHash } from "node:crypto"
import { mkdir, rm } from "node:fs/promises"
import { resolve } from "node:path"
import pinned from "../demo-snapshot.json"

const snapshot: {
  archive: { sha256: string; size: number }
  parts: { key: string; sha256: string; size: number }[]
} = pinned

const root = resolve(import.meta.dir, "..")
const out = resolve(root, "demo-data")
const base = process.env.DEMO_ASSETS_URL ?? "https://assets.chek.page"
const mark = Bun.file(resolve(out, ".snapshot"))
const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex")

if ((await mark.exists()) && (await mark.text()) === snapshot.archive.sha256) {
  console.log("demo-data already holds the pinned snapshot")
  process.exit(0)
}

const archive = new Uint8Array(snapshot.archive.size)
let offset = 0
for (const part of snapshot.parts) {
  const response = await fetch(`${base}/${part.key}`)
  if (!response.ok) throw new Error(`${base}/${part.key} answered ${response.status}`)
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (bytes.length !== part.size || sha256(bytes) !== part.sha256) {
    throw new Error(`${part.key} isn't the part demo-snapshot.json pins`)
  }
  archive.set(bytes, offset)
  offset += bytes.length
  console.log(`${part.key} (${offset} of ${snapshot.archive.size} bytes)`)
}
if (sha256(archive) !== snapshot.archive.sha256) {
  throw new Error("The parts don't join into the archive demo-snapshot.json pins")
}

await rm(out, { recursive: true, force: true })
await mkdir(out, { recursive: true })
const tar = Bun.spawn(["tar", "-C", out, "-xf", "-"], { stdin: archive, stderr: "inherit" })
if ((await tar.exited) !== 0) throw new Error("Couldn't unpack the demo's library")
await Bun.write(mark, snapshot.archive.sha256)
