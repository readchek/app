import { defineConfig } from "cf/config"

export default defineConfig({
  accountId: "bf288a8d0e450c22157076593bc1f6be",
  worker: {
    name: "chek-web",
    compatibilityDate: "2026-10-08",
    domains: ["app.chek.page"],
    // Every path is a screen of the one-page app, which routes in the browser.
    assets: { notFoundHandling: "single-page-application" },
  },
})
