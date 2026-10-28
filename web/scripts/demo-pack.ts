// Packs the demo's library snapshot in demo-data/ for assets.chek.page, in
// parts small enough to upload from Cloudflare's dashboard, and pins it in
// demo-snapshot.json for scripts/demo-data.ts.
//
//   bun scripts/demo-pack.ts [out]
//
// Then upload every part in `out` to the assets.chek.page bucket under the
// key it's named by, and commit demo-snapshot.json.
import { createHash } from "node:crypto"
import { mkdir } from "node:fs/promises"
import { resolve } from "node:path"

const root = resolve(import.meta.dir, "..")
const out = resolve(Bun.argv[2] ?? resolve(root, "demo-pack"))
const partSize = 32 * 1024 * 1024
const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex")

// Sorted names and fixed owners and times, so the same library packs to the same bytes.
const tar = Bun.spawnSync(
  [
    "tar",
    "--sort=name",
    "--owner=0",
    "--group=0",
    "--numeric-owner",
    "--mtime=@0",
    "-C",
    resolve(root, "demo-data"),
    "-cf",
    "-",
    "catalog.json",
    "files",
  ],
  { stdout: "pipe", stderr: "inherit", maxBuffer: 2 ** 31 },
)
if (!tar.success) process.exit(1)
const archive = new Uint8Array(tar.stdout)
const hash = sha256(archive)

const parts = []
for (let offset = 0, index = 0; offset < archive.length; offset += partSize, index++) {
  const bytes = archive.subarray(offset, offset + partSize)
  const key = `demo-snapshot/${hash}/part-${String(index).padStart(3, "0")}`
  await mkdir(resolve(out, key, ".."), { recursive: true })
  await Bun.write(resolve(out, key), bytes)
  parts.push({ key, sha256: sha256(bytes), size: bytes.length })
}

await Bun.write(
  resolve(root, "demo-snapshot.json"),
  `${JSON.stringify({ archive: { sha256: hash, size: archive.length }, parts }, null, 2)}\n`,
)
console.log(`${parts.length} parts in ${out}/demo-snapshot/${hash}`)
