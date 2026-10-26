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
import { ContentSettings } from "./routes/ContentSettings.tsx"
import { AppShell } from "./app/AppShell.tsx"
import { Home } from "./app/Home.tsx"
import { AccountSettings } from "./app/settings/AccountSettings.tsx"
import { Settings as AppSettings } from "./app/settings/Settings.tsx"
import { AddServer } from "./app/SignIn.tsx"
import { Reader } from "./app/reader/Reader.tsx"
import { SiteReader } from "./app/reader/SiteReader.tsx"
import { Search } from "./app/Search.tsx"
import { Book } from "./app/shared/Book.tsx"
import { Library } from "./app/shared/Library.tsx"
import { Series } from "./app/shared/Series.tsx"
import { Shared } from "./app/shared/Shared.tsx"
import { ManageSites } from "./app/sites/ManageSites.tsx"
import { Site } from "./app/sites/Site.tsx"
import { SiteSeries } from "./app/sites/SiteSeries.tsx"
import { Sites } from "./app/sites/Sites.tsx"
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
      <a href="/" class={buttonVariants()}>
        Go to Reading Now
      </a>
    </Page>
  ),
})

// The reading app: every screen inside the shell, which welcomes people
// who haven't signed in to a server yet.
const app = createRoute({ getParentRoute: () => root, id: "app", component: AppShell })

const home = createRoute({ getParentRoute: () => app, path: "/", component: Home })

const shared = createRoute({ getParentRoute: () => app, path: "/shared", component: Shared })

const library = createRoute({
  getParentRoute: () => app,
  path: "/shared/$server/libraries/$libraryId",
  component: Library,
})

const series = createRoute({
  getParentRoute: () => app,
  path: "/shared/$server/series/$seriesId",
  component: Series,
})

const book = createRoute({
  getParentRoute: () => app,
  path: "/shared/$server/books/$publicationId",
  component: Book,
})

const sites = createRoute({ getParentRoute: () => app, path: "/sites", component: Sites })

// `server` is the account's key, as everywhere; `$extensionId` the
// extension's reverse-DNS id. Site series ids are the site's own and can
// hold anything, so they go in the query.
const manageSites = createRoute({
  getParentRoute: () => app,
  path: "/sites/$server/manage",
  component: ManageSites,
})

const site = createRoute({
  getParentRoute: () => app,
  path: "/sites/$server/$extensionId",
  validateSearch: (search: Record<string, unknown>): { q?: string } =>
    typeof search.q === "string" && search.q ? { q: search.q } : {},
  component: Site,
})

const siteSeries = createRoute({
  getParentRoute: () => app,
  path: "/sites/$server/$extensionId/series",
  validateSearch: (search: Record<string, unknown>): { id: string } => ({
    id: typeof search.id === "string" ? search.id : String(search.id ?? ""),
  }),
  component: SiteSeries,
})

const searchRoute = createRoute({
  getParentRoute: () => app,
  path: "/search",
  validateSearch: (search: Record<string, unknown>): { q?: string } =>
    typeof search.q === "string" && search.q ? { q: search.q } : {},
  component: Search,
})

const settings = createRoute({
  getParentRoute: () => app,
  path: "/settings",
  component: AppSettings,
})

const accountSettings = createRoute({
  getParentRoute: () => app,
  path: "/settings/$server",
  component: AccountSettings,
})

// `server` fills in the address, such as when a session ended. The iOS
// app's link also carries a one-time sign-in code in the fragment.
const signInRoute = createRoute({
  getParentRoute: () => app,
  path: "/sign-in",
  validateSearch: (search: Record<string, unknown>): { server?: string } => {
    const server = search.server
    return typeof server === "string" && server ? { server } : {}
  },
  component: AddServer,
})

// A publication open full screen, outside the shell. `server` is the
// account's host, as accountKey makes it.
const read = createRoute({
  getParentRoute: () => root,
  path: "/read/$server/$publicationId",
  component: Reader,
})

// A chapter read straight from a site. The link brings the chapter's
// title, since the server can't be asked for one chapter alone.
const chapter = createRoute({
  getParentRoute: () => root,
  path: "/chapter/$server/$extensionId",
  validateSearch: (
    search: Record<string, unknown>,
  ): { series: string; chapter: string; title?: string } => ({
    series: String(search.series ?? ""),
    chapter: String(search.chapter ?? ""),
    ...(typeof search.title === "string" && search.title ? { title: search.title } : {}),
  }),
  component: SiteReader,
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
    app.addChildren([
      home,
      shared,
      library,
      series,
      book,
      sites,
      manageSites,
      site,
      siteSeries,
      searchRoute,
      settings,
      accountSettings,
      signInRoute,
    ]),
    read,
    chapter,
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

// Installed, the app opens without a connection. Only built apps register
// it, so development always loads fresh files.
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  void navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`).catch(() => {})
}
