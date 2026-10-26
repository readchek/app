import { For, type JSX, Show } from "solid-js"
import { Link, Outlet, useRouter } from "@tanstack/solid-router"
import { Wordmark } from "../components/Wordmark.tsx"
import { BookOpen, Building, ChevronLeft, Gear, Search } from "../components/icons.tsx"
import { Button } from "../components/ui/button.tsx"
import { cn } from "../lib/cn.ts"
import { accounts } from "./accounts.ts"
import { Welcome } from "./SignIn.tsx"

// The app's places, as the iOS app's tabs. On a wide window they're a
// sidebar, as on iPad; on a phone they're a bar along the bottom.
const places = [
  { to: "/", label: "Reading Now", icon: BookOpen },
  { to: "/shared", label: "Shared", icon: Building },
  { to: "/search", label: "Search", icon: Search },
  { to: "/settings", label: "Settings", icon: Gear },
] as const

/** The frame of every reading screen, or the welcome when no server is signed in yet. */
export function AppShell() {
  return (
    <Show when={accounts().length > 0} fallback={<Welcome />}>
      <div class="min-h-dvh lg:grid lg:grid-cols-[15rem_1fr]">
        <aside class="sticky top-0 hidden h-dvh flex-col border-e bg-card/40 px-4 pt-8 pb-6 lg:flex">
          <Link
            to="/"
            aria-label="Chek, Reading Now"
            class="ms-2 inline-block self-start text-link"
          >
            <Wordmark />
          </Link>
          <nav aria-label="Chek" class="mt-8 grid gap-0.5">
            <For each={places}>
              {(place) => (
                <Link
                  to={place.to}
                  activeOptions={{ exact: place.to === "/" }}
                  class="flex h-10 items-center gap-3 rounded-lg px-3 text-[15px] font-semibold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground data-[status=active]:bg-muted data-[status=active]:text-foreground [&_svg]:size-5 [&_svg]:text-link"
                  activeProps={{ "aria-current": "page" }}
                >
                  <place.icon />
                  {place.label}
                </Link>
              )}
            </For>
          </nav>
          <p class="mt-auto px-3 text-sm text-muted-foreground">
            For the love of the next chapter.
          </p>
        </aside>
        <div class="min-w-0 pb-[calc(4.5rem+env(safe-area-inset-bottom))] lg:pb-0">
          <Outlet />
        </div>
        <nav
          aria-label="Chek"
          class="fixed inset-x-0 bottom-0 z-40 flex justify-around border-t bg-background/85 px-2 pt-1.5 pb-[calc(0.375rem+env(safe-area-inset-bottom))] backdrop-blur-xl lg:hidden"
        >
          <For each={places}>
            {(place) => (
              <Link
                to={place.to}
                activeOptions={{ exact: place.to === "/" }}
                class="flex min-w-16 flex-col items-center gap-0.5 rounded-lg px-3 py-1 text-[11px] font-semibold text-muted-foreground data-[status=active]:text-link [&_svg]:size-6"
                activeProps={{ "aria-current": "page" }}
              >
                <place.icon />
                {place.label}
              </Link>
            )}
          </For>
        </nav>
      </div>
    </Show>
  )
}

/** Goes back where the person came from, or to `fallback` when they opened this screen directly. */
export function BackButton(props: { label: string; fallback: () => void }) {
  const router = useRouter()
  return (
    <Button
      variant="ghost"
      size="sm"
      class="-ms-3 mb-4 text-link [&_svg]:size-5"
      onClick={() => (router.history.canGoBack() ? router.history.back() : props.fallback())}
    >
      <ChevronLeft />
      {props.label}
    </Button>
  )
}

/** A reading screen's large title, as the iOS app's, and its content. Screens that draw their own title pass an empty one. */
export function Screen(props: {
  title: string
  back?: JSX.Element
  lead?: JSX.Element
  actions?: JSX.Element
  narrow?: boolean
  children: JSX.Element
}) {
  return (
    <main
      class={cn(
        "mx-auto w-full px-5 pt-8 pb-16 sm:px-8 lg:pt-12",
        props.narrow ? "max-w-2xl" : "max-w-7xl",
      )}
    >
      {props.back}
      <Show when={props.title}>
        <header class="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div class="min-w-0">
            <h1 class="text-[34px] leading-none tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
              {props.title}
            </h1>
            <Show when={props.lead}>
              <p class="mt-2.5 text-[17px] leading-snug text-muted-foreground">{props.lead}</p>
            </Show>
          </div>
          {props.actions}
        </header>
      </Show>
      {props.children}
    </main>
  )
}
