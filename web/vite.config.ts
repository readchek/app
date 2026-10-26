import { readFileSync, readdirSync, statSync } from "node:fs"
import { createRequire } from "node:module"
import { dirname, join } from "node:path"
import { type Plugin, defineConfig } from "vite"
import solid from "vite-plugin-solid"
import tailwindcss from "@tailwindcss/vite"

const require = createRequire(import.meta.url)
const packageDirectory = (name: string) => dirname(require.resolve(`${name}/package.json`))

/** Every file under `directory`, by its path inside it. */
function filesIn(directory: string, prefix = ""): Map<string, string> {
  const files = new Map<string, string>()
  for (const name of readdirSync(directory)) {
    const path = join(directory, name)
    if (statSync(path).isDirectory()) {
      for (const [inner, full] of filesIn(path, `${prefix}${name}/`)) files.set(inner, full)
    } else {
      files.set(`${prefix}${name}`, path)
    }
  }
  return files
}

const types: Record<string, string> = {
  html: "text/html",
  js: "text/javascript",
  mjs: "text/javascript",
}

// Serves `files` at /`folder`/ in development and copies them into the
// build there, unbundled and unhashed, for code that loads them by name.
function served(folder: string, files: Map<string, string>): Plugin {
  return {
    name: `served-${folder}`,
    configureServer(server) {
      server.middlewares.use(`/${folder}`, (request, response, next) => {
        const path = files.get(
          decodeURIComponent((request.url ?? "").split("?")[0]!.replace(/^\//, "")),
        )
        if (!path) return next()
        response.setHeader(
          "Content-Type",
          types[path.split(".").pop()!] ?? "application/octet-stream",
        )
        response.end(readFileSync(path))
      })
    },
    generateBundle() {
      for (const [name, path] of files) {
        this.emitFile({ type: "asset", fileName: `${folder}/${name}`, source: readFileSync(path) })
      }
    },
  }
}

// The book reader draws each page in a sandboxed frame that Chek Reader
// ships as plain files.
const readerFrame = new Map(
  [...filesIn(join(packageDirectory("@readchek/reader"), "Web/dist/frame"))].filter(
    ([name]) => !name.endsWith(".d.ts"),
  ),
)

// pdf.js's worker, and the character maps and standard fonts it fetches
// for PDFs that don't embed their fonts.
const pdfjs = packageDirectory("pdfjs-dist")
const pdfFiles = new Map([
  ["pdf.worker.min.mjs", join(pdfjs, "build/pdf.worker.min.mjs")],
  ...[...filesIn(join(pdfjs, "cmaps"))].map(([name, path]) => [`cmaps/${name}`, path] as const),
  ...[...filesIn(join(pdfjs, "standard_fonts"))].map(
    ([name, path]) => [`standard_fonts/${name}`, path] as const,
  ),
])

export default defineConfig({
  plugins: [solid(), tailwindcss(), served("reader-frame", readerFrame), served("pdfjs", pdfFiles)],
  server: { port: 18358 },
})
