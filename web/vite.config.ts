import { readFileSync, readdirSync } from "node:fs"
import { createRequire } from "node:module"
import { dirname, join } from "node:path"
import { type Plugin, defineConfig } from "vite"
import solid from "vite-plugin-solid"
import tailwindcss from "@tailwindcss/vite"

// The book reader draws each page in a sandboxed frame that Chek Reader
// ships as plain files. They're served at /reader-frame/, unbundled and
// unhashed, since the frame loads them by name.
function readerFrame(): Plugin {
  const directory = join(
    dirname(createRequire(import.meta.url).resolve("@readchek/reader/package.json")),
    "Web/dist/frame",
  )
  const files = readdirSync(directory).filter((name) => !name.endsWith(".d.ts"))
  const types: Record<string, string> = { html: "text/html", js: "text/javascript" }
  return {
    name: "reader-frame",
    configureServer(server) {
      server.middlewares.use("/reader-frame", (request, response, next) => {
        const name = (request.url ?? "").split("?")[0]!.replace(/^\//, "")
        if (!files.includes(name)) return next()
        response.setHeader("Content-Type", types[name.split(".").pop()!] ?? "text/plain")
        response.end(readFileSync(join(directory, name)))
      })
    },
    generateBundle() {
      for (const name of files) {
        this.emitFile({
          type: "asset",
          fileName: `reader-frame/${name}`,
          source: readFileSync(join(directory, name)),
        })
      }
    },
  }
}

export default defineConfig({
  plugins: [solid(), tailwindcss(), readerFrame()],
  server: { port: 18358 },
})
