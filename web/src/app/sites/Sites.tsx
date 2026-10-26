import { For, Match, Show, Switch, createResource } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { ChevronRight, Globe } from "../../components/icons.tsx"
import { Badge } from "../../components/ui/badge.tsx"
import { buttonVariants } from "../../components/ui/button.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { type Account, accountKey, accounts, host } from "../accounts.ts"
import { Screen } from "../AppShell.tsx"
import { coverPath, recentlyAdded } from "../client.ts"
import { Cover } from "../Cover.tsx"
import { Shelf, ShelfItem, ShelfPlaceholder } from "../Shelf.tsx"
import { Failure } from "../shared/Library.tsx"
import { readableLibraries } from "../shared/data.ts"
import { publicationTitle, seriesTitle } from "../titles.ts"
import { installedExtensions } from "./api.ts"
import { siteHost } from "./titles.ts"

/** Sites: the extensions you've added on each server, and the new chapters of series it follows. */
export function Sites() {
  const signedIn = () => accounts().filter((a) => !a.expired)
  return (
    <Screen title="Sites" lead="Read from the websites your Chek servers can reach.">
      <For each={signedIn()}>
        {(account) => <ServerSites account={account} showHost={signedIn().length > 1} />}
      </For>
    </Screen>
  )
}

function ServerSites(props: { account: Account; showHost: boolean }) {
  const [list] = createResource(
    () => props.account,
    (account) => installedExtensions(account),
  )
  // Series followed from a site land in a library that runs on its
  // extension; their newest chapters show here, as on iOS's Updates.
  const [followed] = createResource(
    () => props.account,
    async (account) =>
      (await readableLibraries(account)).filter((library) => library.source?.type === "extension"),
  )

  return (
    <section class="mb-12">
      <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
        <h2 class="text-[22px] leading-tight tracking-[-0.03em]">
          {props.showHost ? host(props.account.server) : "Your sites"}
        </h2>
        <Show when={!props.account.user.demo}>
          <Link
            to="/sites/$server/manage"
            params={{ server: accountKey(props.account) }}
            class={buttonVariants({ variant: "outline", size: "sm" })}
          >
            Add or remove sites
          </Link>
        </Show>
      </div>
      <Switch>
        <Match when={list.error}>
          <Failure error={list.error} />
        </Match>
        <Match when={list()}>
          {(extensions) => (
            <Show
              when={extensions().length > 0}
              fallback={
                <p class="max-w-2xl text-[15px] text-muted-foreground">
                  No sites yet. Add one to search it and read its series here.
                </p>
              }
            >
              <ul class="max-w-2xl divide-y border-y">
                <For each={extensions()}>
                  {(extension) => (
                    <li>
                      <Link
                        to="/sites/$server/$extensionId"
                        params={{ server: accountKey(props.account), extensionId: extension.id }}
                        class="flex items-center gap-3.5 py-3.5 transition-colors hover:text-link focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none [&>svg:first-child]:size-6 [&>svg:first-child]:shrink-0 [&>svg:first-child]:text-link"
                      >
                        <Globe />
                        <span class="min-w-0 flex-1">
                          <span class="block truncate text-[17px]">{extension.name}</span>
                          <span class="block truncate text-[13px] text-muted-foreground">
                            {extension.sites.map(siteHost).join(", ")}
                          </span>
                        </span>
                        <Show when={!extension.usable}>
                          <Badge variant="destructive">Turned off</Badge>
                        </Show>
                        <Show when={extension.usable && extension.update}>
                          <Badge variant="butter">Update</Badge>
                        </Show>
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
          <div class="max-w-2xl divide-y border-y" aria-hidden="true">
            <For each={[0, 1]}>
              {() => (
                <div class="flex items-center gap-3.5 py-4">
                  <Skeleton class="size-6 rounded-full" />
                  <Skeleton class="h-4 w-48" />
                </div>
              )}
            </For>
          </div>
        </Match>
      </Switch>

      <For each={followed() ?? []}>
        {(library) => (
          <NewChapters account={props.account} libraryId={library.id} name={library.name} />
        )}
      </For>
    </section>
  )
}

function NewChapters(props: { account: Account; libraryId: number; name: string }) {
  const [latest] = createResource(
    () => ({ account: props.account, libraryId: props.libraryId }),
    ({ account, libraryId }) => recentlyAdded(account, { libraryId, limit: 20 }),
  )
  return (
    <div class="mt-10">
      <Switch>
        <Match when={latest()}>
          {(page) => (
            <Show when={page().items.length > 0}>
              <Shelf title={`New in ${props.name}`}>
                <For each={page().items}>
                  {(publication) => (
                    <ShelfItem
                      to={{ server: accountKey(props.account), read: publication.id }}
                      cover={
                        <Cover
                          account={props.account}
                          path={publication.hasCover ? coverPath(publication) : undefined}
                          title={publicationTitle(publication)}
                        />
                      }
                      title={publicationTitle(publication)}
                      detail={seriesTitle(publication)}
                    />
                  )}
                </For>
              </Shelf>
            </Show>
          )}
        </Match>
        <Match when={latest.loading}>
          <ShelfPlaceholder />
        </Match>
      </Switch>
    </div>
  )
}
