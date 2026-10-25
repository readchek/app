import { render } from "solid-js/web"
import {
  Outlet,
  RouterProvider,
  createRootRoute,
  createRoute,
  createRouter,
  redirect,
} from "@tanstack/solid-router"
import { ContentSettings } from "./routes/ContentSettings.tsx"
import "./styles.css"

const root = createRootRoute({
  component: () => (
    <main>
      <header class="brand">
        <img src="/mark.svg" alt="" width="28" height="28" />
        <span>Chek</span>
      </header>
      <Outlet />
    </main>
  ),
  notFoundComponent: () => (
    <section>
      <h1>Page not found</h1>
      <p>
        <a href="/settings/content">Go to content settings</a>
      </p>
    </section>
  ),
})

// Content settings are the only screen so far, so the app opens on it.
const home = createRoute({
  getParentRoute: () => root,
  path: "/",
  beforeLoad: () => {
    throw redirect({ to: "/settings/content", replace: true })
  },
})

export const contentSettings = createRoute({
  getParentRoute: () => root,
  path: "/settings/content",
  // `server` is the Chek server the app opened this page for. The app puts
  // its one-time sign-in code in the fragment, which browsers never send.
  validateSearch: (search: Record<string, unknown>): { server?: string } => {
    const server = search.server
    return typeof server === "string" && server ? { server } : {}
  },
  component: ContentSettings,
})

const router = createRouter({ routeTree: root.addChildren([home, contentSettings]) })

declare module "@tanstack/solid-router" {
  interface Register {
    router: typeof router
  }
}

render(() => <RouterProvider router={router} />, document.getElementById("root")!)
