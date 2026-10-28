import { For, Match, Show, Switch, createSignal } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { AlertCircle, ArrowUp, ChevronRight, Folder } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button } from "../components/ui/button.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../components/ui/dialog.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"
import { adminSession } from "./AdminShell.tsx"
import { folders } from "./api.ts"
import { call, message } from "./util.ts"

const row =
  "flex w-full items-center gap-3 py-3 text-start transition-colors hover:text-link focus-visible:text-link focus-visible:outline-none [&>svg]:size-[18px] [&>svg]:shrink-0"

/** Browses the server's folders, so a folder library's path is picked rather than typed. */
export function FolderPicker(props: {
  open: boolean
  onOpenChange: (open: boolean) => void
  start?: string
  onPick: (path: string) => void
}) {
  const session = adminSession()
  const [path, setPath] = createSignal<string | undefined>()
  // Opens where the path field points; if that isn't a folder, at the top.
  const [listing] = createResource(
    () => (props.open ? (path() ?? (props.start || "/")) : undefined),
    async (wanted) => {
      try {
        return await call(folders(session, wanted))
      } catch (error) {
        if (wanted !== "/" && path() === undefined) return call(folders(session, "/"))
        throw error
      }
    },
  )

  const close = (open: boolean) => {
    if (!open) setPath(undefined)
    props.onOpenChange(open)
  }

  return (
    <Dialog open={props.open} onOpenChange={close}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Choose a folder</DialogTitle>
          <DialogDescription>
            Folders on the server. With Docker, these are inside the container, so mount your
            library into it first.
          </DialogDescription>
        </DialogHeader>
        <div class="grid gap-3">
          <p class="truncate rounded-xl bg-muted px-3.5 py-2.5 font-mono text-[13px]" dir="ltr">
            {listing.latest?.path ?? path() ?? props.start ?? "/"}
          </p>
          <Switch>
            <Match when={listing.error}>
              <Alert variant="destructive">
                <AlertCircle />
                <p>{message(listing.error)}</p>
              </Alert>
            </Match>
            <Match when={listing.latest}>
              {(current) => (
                <ul
                  class="max-h-[45dvh] divide-y overflow-y-auto border-y"
                  aria-busy={listing.loading}
                >
                  <Show when={current().parent}>
                    {(parent) => (
                      <li>
                        <button type="button" class={row} onClick={() => setPath(parent())}>
                          <ArrowUp />
                          <span class="flex-1 text-muted-foreground">Up one folder</span>
                        </button>
                      </li>
                    )}
                  </Show>
                  <For
                    each={current().folders}
                    fallback={
                      <li class="py-3 text-[15px] text-muted-foreground">No folders in here.</li>
                    }
                  >
                    {(folder) => (
                      <li>
                        <button type="button" class={row} onClick={() => setPath(folder.path)}>
                          <Folder />
                          <span class="min-w-0 flex-1 truncate">{folder.name}</span>
                          <ChevronRight />
                        </button>
                      </li>
                    )}
                  </For>
                  <Show when={current().truncated}>
                    <li class="py-3 text-sm text-muted-foreground">
                      Only the first 1,000 folders are shown. Type the path instead.
                    </li>
                  </Show>
                </ul>
              )}
            </Match>
            <Match when={true}>
              <div class="grid gap-3 border-y py-3">
                <Skeleton class="h-5 w-40" />
                <Skeleton class="h-5 w-52" />
                <Skeleton class="h-5 w-32" />
              </div>
            </Match>
          </Switch>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => close(false)}>
            Cancel
          </Button>
          <Button
            disabled={!listing.latest || listing.loading}
            onClick={() => {
              const chosen = listing.latest?.path
              if (!chosen) return
              props.onPick(chosen)
              close(false)
            }}
          >
            Choose this folder
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
