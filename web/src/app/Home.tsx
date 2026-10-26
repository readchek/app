import { For, Match, Show, Switch, createResource } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { AlertCircle } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { buttonVariants } from "../components/ui/button.tsx"
import { type Account, accountKey, accounts, host } from "./accounts.ts"
import { type Continued, continueReading, coverPath, recentlyAdded } from "./client.ts"
import { Cover } from "./Cover.tsx"
import { Screen } from "./AppShell.tsx"
import { Shelf, ShelfItem, ShelfPlaceholder } from "./Shelf.tsx"
import { progressCaption, publicationTitle, seriesTitle } from "./titles.ts"

const shelfSize = 20

/** Reading Now: what you're reading on every server first, then what's new on each. */
export function Home() {
  const signedIn = () => accounts().filter((a) => !a.expired)
  const expired = () => accounts().filter((a) => a.expired)

  return (
    <Screen title="Reading Now">
      <For each={expired()}>
        {(account) => (
          <Alert variant="destructive" class="mb-8">
            <AlertCircle />
            <p>
              You were signed out of {host(account.server)}.{" "}
              <Link
                to="/sign-in"
                search={{ server: account.server }}
                class={buttonVariants({ variant: "link", size: "inline" })}
              >
                Sign in again
              </Link>
            </p>
          </Alert>
        )}
      </For>
      <ContinueReading accounts={signedIn()} />
      <For each={signedIn()}>
        {(account) => <RecentlyAdded account={account} showHost={accounts().length > 1} />}
      </For>
    </Screen>
  )
}

type Reading = Continued & { account: Account }

function ContinueReading(props: { accounts: Account[] }) {
  // One shelf for every server, most recently read first. A server that
  // can't be reached leaves out only its own books.
  const [reading] = createResource(
    () => props.accounts,
    async (list) => {
      const pages = await Promise.allSettled(
        list.map(async (account) =>
          (await continueReading(account, { limit: shelfSize })).items.map((item): Reading => ({
            ...item,
            account,
          })),
        ),
      )
      return pages
        .flatMap((page) => (page.status === "fulfilled" ? page.value : []))
        .sort((a, b) => (b.progress.updatedAt ?? "").localeCompare(a.progress.updatedAt ?? ""))
        .slice(0, shelfSize)
    },
  )

  return (
    <Switch>
      <Match when={reading.loading && !reading.latest}>
        <ShelfPlaceholder featured />
      </Match>
      <Match when={reading()?.length}>
        <Shelf title="Continue Reading">
          <For each={reading()}>
            {(item) => (
              <ShelfItem
                featured
                to={{ server: accountKey(item.account), read: item.publication.id }}
                cover={
                  <Cover
                    account={item.account}
                    path={item.publication.hasCover ? coverPath(item.publication) : undefined}
                    title={publicationTitle(item.publication)}
                  />
                }
                title={publicationTitle(item.publication)}
                detail={[seriesTitle(item.publication), progressCaption(item.progress)]
                  .filter(Boolean)
                  .join(" · ")}
              />
            )}
          </For>
        </Shelf>
      </Match>
    </Switch>
  )
}

function RecentlyAdded(props: { account: Account; showHost: boolean }) {
  const [added] = createResource(
    () => props.account,
    (account) => recentlyAdded(account, { limit: shelfSize }),
  )
  const detail = () => (props.showHost ? host(props.account.server) : undefined)

  return (
    <Switch>
      <Match when={added.error}>
        <section class="mb-10">
          <h2 class="mb-3 text-[22px] leading-tight tracking-[-0.03em]">Recently Added</h2>
          <Alert variant="destructive">
            <AlertCircle />
            <p>
              {added.error instanceof Error
                ? added.error.message
                : "Couldn't load this server's books."}
            </p>
          </Alert>
        </section>
      </Match>
      <Match when={added()}>
        {(page) => (
          <Show
            when={page().items.length > 0}
            fallback={
              <section class="mb-10">
                <h2 class="mb-2 text-[22px] leading-tight tracking-[-0.03em]">Recently Added</h2>
                <p class="text-[15px] text-muted-foreground">
                  Nothing on {host(props.account.server)} yet. Books and comics show up here once
                  its admin adds a library.
                </p>
              </section>
            }
          >
            <Shelf title="Recently Added" detail={detail()}>
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
      <Match when={true}>
        <ShelfPlaceholder />
      </Match>
    </Switch>
  )
}
