import { For, Match, Switch, createEffect, onCleanup } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { Link } from "@tanstack/solid-router"
import { AlertCircle, ChevronRight, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Badge } from "../components/ui/badge.tsx"
import { buttonVariants } from "../components/ui/button.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"
import { Heading, adminSession } from "./AdminShell.tsx"
import { type Library, libraries } from "./api.ts"
import { ago, call, message } from "./util.ts"

/** Scans report only when asked, so lists ask again this often while one runs. */
export const SCAN_POLL_MS = 2000

/** Where a library reads from, in a few words. */
export function origin(library: Library): string {
  if (library.kind === "folder") return library.path ?? "Folder"
  const source = library.source
  if (!source) return "Source"
  const host = source.url ? new URL(source.url).host : undefined
  switch (source.type) {
    case "komga":
      return `Komga at ${host}`
    case "kavita":
      return `Kavita at ${host}`
    case "extension":
      return `Series followed through ${source.extensionId}`
  }
}

/** A library's last scan, as a badge and a line, or the scan going on now. */
export function ScanStatus(props: { library: Library }) {
  return (
    <Switch>
      <Match when={props.library.scan.status === "scanning"}>
        <Badge variant="secondary" class="gap-1.5">
          <Spinner class="size-3" />
          Scanning
        </Badge>
      </Match>
      <Match when={props.library.scan.status === "failed"}>
        <Badge variant="destructive">Scan failed</Badge>
      </Match>
      <Match when={props.library.scan.finishedAt}>
        {(finished) => <span class="text-sm text-muted-foreground">Scanned {ago(finished())}</span>}
      </Match>
    </Switch>
  )
}

export function Libraries() {
  const session = adminSession()
  const [list, { refetch }] = createResource(() => call(libraries(session)))

  createEffect(() => {
    if (!list()?.some((l) => l.scan.status === "scanning")) return
    const timer = setInterval(() => void refetch(), SCAN_POLL_MS)
    onCleanup(() => clearInterval(timer))
  })

  return (
    <>
      <Heading title="Libraries" lead="Folders and servers that Chek reads books and comics from.">
        <Link to="/admin/libraries/new" search={{}} class={buttonVariants({ size: "sm" })}>
          Add library
        </Link>
      </Heading>
      <Switch>
        <Match when={list.error}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{message(list.error)}</p>
          </Alert>
        </Match>
        <Match when={list()?.length === 0}>
          <div class="grid justify-items-start gap-4 border-y py-8">
            <p class="text-[15px] leading-relaxed text-muted-foreground">
              No libraries yet. Add a folder on this server, or a Komga or Kavita server, and Chek
              scans it for books and comics.
            </p>
            <Link to="/admin/libraries/new" search={{}} class={buttonVariants()}>
              Add your first library
            </Link>
          </div>
        </Match>
        <Match when={list()}>
          {(items) => (
            <ul class="divide-y border-y">
              <For each={items()}>
                {(library) => (
                  <li>
                    <Link
                      to="/admin/libraries/$libraryId"
                      params={{ libraryId: String(library.id) }}
                      class="-mx-3 flex items-center gap-4 rounded-xl px-3 py-4 transition-colors hover:bg-muted/60 focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
                    >
                      <span class="grid min-w-0 flex-1 gap-0.5">
                        <span class="truncate font-semibold">{library.name}</span>
                        <span class="truncate text-[15px] text-muted-foreground">
                          {origin(library)}
                        </span>
                        <span class="sm:hidden">
                          <ScanStatus library={library} />
                        </span>
                      </span>
                      <span class="hidden sm:block">
                        <ScanStatus library={library} />
                      </span>
                      <ChevronRight />
                    </Link>
                  </li>
                )}
              </For>
            </ul>
          )}
        </Match>
        <Match when={true}>
          <div aria-busy="true" class="divide-y border-y">
            <p class="sr-only" role="status">
              Loading…
            </p>
            <For each={[0, 1, 2]}>
              {() => (
                <div class="grid gap-2 py-4">
                  <Skeleton class="h-4 w-32" />
                  <Skeleton class="h-4 w-56" />
                </div>
              )}
            </For>
          </div>
        </Match>
      </Switch>
    </>
  )
}
