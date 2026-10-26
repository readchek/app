import { For, Match, Show, Switch, createResource } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { AlertCircle, Books, ChevronRight } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { type Account, accountKey, accounts, host } from "../accounts.ts"
import { Screen } from "../AppShell.tsx"
import { readableLibraries } from "./data.ts"

/** Shared: the libraries on every server you're signed in to. */
export function Shared() {
  const signedIn = () => accounts().filter((a) => !a.expired)
  return (
    <Screen title="Shared" lead="The libraries your Chek servers share with you." narrow>
      <For each={signedIn()}>
        {(account) => <ServerLibraries account={account} showHost={signedIn().length > 1} />}
      </For>
    </Screen>
  )
}

function ServerLibraries(props: { account: Account; showHost: boolean }) {
  const [list] = createResource(() => props.account, readableLibraries)

  return (
    <section class="mb-10">
      <Show when={props.showHost}>
        <h2 class="mb-1 text-[22px] leading-tight tracking-[-0.03em]">
          {host(props.account.server)}
        </h2>
      </Show>
      <Switch>
        <Match when={list.error}>
          <Alert variant="destructive" class="mt-3">
            <AlertCircle />
            <p>
              {list.error instanceof Error ? list.error.message : "Couldn't load its libraries."}
            </p>
          </Alert>
        </Match>
        <Match when={list()}>
          {(libraries) => (
            <Show
              when={libraries().length > 0}
              fallback={
                <p class="mt-2 text-[15px] text-muted-foreground">
                  No libraries yet. They show up here once the server's admin adds one and gives you
                  access.
                </p>
              }
            >
              <ul class="divide-y border-y">
                <For each={libraries()}>
                  {(library) => (
                    <li>
                      <Link
                        to="/shared/$server/libraries/$libraryId"
                        params={{
                          server: accountKey(props.account),
                          libraryId: String(library.id),
                        }}
                        class="flex items-center gap-3.5 py-4 text-[17px] transition-colors hover:text-link focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none [&>svg:first-child]:size-6 [&>svg:first-child]:text-link"
                      >
                        <Books />
                        <span class="min-w-0 flex-1 truncate">{library.name}</span>
                        <ChevronRight />
                      </Link>
                    </li>
                  )}
                </For>
              </ul>
            </Show>
          )}
        </Match>
        <Match when={true}>
          <div class="divide-y border-y" aria-hidden="true">
            <For each={[0, 1, 2]}>
              {() => (
                <div class="flex items-center gap-3.5 py-4">
                  <Skeleton class="size-6 rounded" />
                  <Skeleton class="h-4 w-40" />
                </div>
              )}
            </For>
          </div>
        </Match>
      </Switch>
    </section>
  )
}
