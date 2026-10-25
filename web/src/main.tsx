import { render } from "solid-js/web"
import {
  Outlet,
  RouterProvider,
  createRootRoute,
  createRoute,
  createRouter,
  redirect,
} from "@tanstack/solid-router"
import { Page } from "./components/Page.tsx"
import { buttonVariants } from "./components/ui/button.tsx"
import { Card, CardContent } from "./components/ui/card.tsx"
import { ContentSettings } from "./routes/ContentSettings.tsx"
import "./styles.css"

const root = createRootRoute({
  component: Outlet,
  notFoundComponent: () => (
    <Page title="Page not found" lead="There's nothing at this address.">
      <Card>
        <CardContent>
          <a href="/settings/content" class={buttonVariants()}>
            Go to content settings
          </a>
        </CardContent>
      </Card>
    </Page>
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
