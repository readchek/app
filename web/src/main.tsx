import { render } from "solid-js/web"
import {
  Outlet,
  RouterProvider,
  createRootRoute,
  createRoute,
  createRouter,
  redirect,
} from "@tanstack/solid-router"
import { bundled } from "./api.ts"
import { Page } from "./components/Page.tsx"
import { buttonVariants } from "./components/ui/button.tsx"
import { ContentSettings } from "./routes/ContentSettings.tsx"
import { AddLibrary } from "./admin/AddLibrary.tsx"
import { AdminShell } from "./admin/AdminShell.tsx"
import { Extensions } from "./admin/Extensions.tsx"
import { Libraries } from "./admin/Libraries.tsx"
import { LibraryDetail } from "./admin/LibraryDetail.tsx"
import { Settings } from "./admin/Settings.tsx"
import { EditUser, NewUser } from "./admin/UserForm.tsx"
import { Users } from "./admin/Users.tsx"
import "./styles.css"

const root = createRootRoute({
  component: Outlet,
  notFoundComponent: () => (
    <Page title="Page not found" lead="There's nothing at this address.">
      <a href={bundled ? "/admin/" : "/settings/content"} class={buttonVariants()}>
        {bundled ? "Go to the admin panel" : "Go to content settings"}
      </a>
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

// The admin panel. The Chek server serves the same screens at its own
// address, built with `bun run build:server`.
const admin = createRoute({
  getParentRoute: () => root,
  path: "/admin",
  // `server` is the Chek server to manage, filled in for the visitor.
  validateSearch: (search: Record<string, unknown>): { server?: string } => {
    const server = search.server
    return typeof server === "string" && server ? { server } : {}
  },
  component: AdminShell,
})

const adminHome = createRoute({
  getParentRoute: () => admin,
  path: "/",
  beforeLoad: () => {
    throw redirect({ to: "/admin/libraries", replace: true })
  },
})

const adminLibraries = createRoute({
  getParentRoute: () => admin,
  path: "/libraries",
  component: Libraries,
})

const adminAddLibrary = createRoute({
  getParentRoute: () => admin,
  path: "/libraries/new",
  // `welcome` when the admin was just made, as the second step of setup.
  validateSearch: (search: Record<string, unknown>): { welcome?: boolean } =>
    search.welcome === true || search.welcome === "true" ? { welcome: true } : {},
  component: AddLibrary,
})

const adminLibrary = createRoute({
  getParentRoute: () => admin,
  path: "/libraries/$libraryId",
  component: LibraryDetail,
})

const adminUsers = createRoute({ getParentRoute: () => admin, path: "/users", component: Users })

const adminNewUser = createRoute({
  getParentRoute: () => admin,
  path: "/users/new",
  component: NewUser,
})

const adminUser = createRoute({
  getParentRoute: () => admin,
  path: "/users/$userId",
  component: EditUser,
})

const adminExtensions = createRoute({
  getParentRoute: () => admin,
  path: "/extensions",
  component: Extensions,
})

const adminSettings = createRoute({
  getParentRoute: () => admin,
  path: "/settings",
  component: Settings,
})

const router = createRouter({
  routeTree: root.addChildren([
    home,
    contentSettings,
    admin.addChildren([
      adminHome,
      adminLibraries,
      adminAddLibrary,
      adminLibrary,
      adminUsers,
      adminNewUser,
      adminUser,
      adminExtensions,
      adminSettings,
    ]),
  ]),
})

declare module "@tanstack/solid-router" {
  interface Register {
    router: typeof router
  }
}

render(() => <RouterProvider router={router} />, document.getElementById("root")!)
