import { For, Match, Show, Switch, createMemo, createSignal } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { useNavigate, useParams } from "@tanstack/solid-router"
import { Spinner } from "../../components/icons.tsx"
import { Badge } from "../../components/ui/badge.tsx"
import { Button } from "../../components/ui/button.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { type Account, host } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
import { Failure } from "../shared/Library.tsx"
import { routeAccount } from "../shared/data.ts"
import {
  type ContentFormat,
  availableExtensions,
  installExtension,
  installedExtensions,
  uninstallExtension,
} from "./api.ts"
import { siteHost } from "./titles.ts"

/** One row: a site offered by a repository, the one you added, or both. */
type Row = {
  id: string
  name: string
  sites: string[]
  formats: ContentFormat[]
  repositoryId: number
  version: string
  installed: string | null
}

const formatNames: Record<ContentFormat, string> = {
  images: "Comics",
  epub: "Books",
  pdf: "PDFs",
}

/** The sites your server's repositories offer, to add, update or remove. */
export function ManageSites() {
  const navigate = useNavigate()
  const params = useParams({ from: "/app/sites/$server/manage" })
  const account = createMemo(() => {
    try {
      return routeAccount(params().server)
    } catch {
      return undefined
    }
  })

  return (
    <Screen
      title="Add or remove sites"
      lead={account() && `The sites ${host(account()!.server)} can read from.`}
      back={<BackButton label="Sites" fallback={() => void navigate({ to: "/sites" })} />}
      narrow
    >
      <Show
        when={account()}
        fallback={
          <Failure error={new Error("You're not signed in to this server. Add it in Settings.")} />
        }
      >
        {(current) => <SiteList account={current()} />}
      </Show>
    </Screen>
  )
}

function SiteList(props: { account: Account }) {
  const [rows, { refetch }] = createResource(
    () => props.account,
    async (account): Promise<Row[]> => {
      const [available, installed] = await Promise.all([
        availableExtensions(account),
        installedExtensions(account),
      ])
      const listed: Row[] = available.map((item) => ({
        id: item.id,
        name: item.name,
        sites: item.sites,
        formats: item.formats,
        repositoryId: item.repositoryId,
        version: item.version,
        installed:
          installed.find((own) => own.id === item.id && own.repositoryId === item.repositoryId)
            ?.version ?? null,
      }))
      // Sites added from a repository that's gone stay removable.
      const orphans = installed
        .filter((own) => !listed.some((row) => row.id === own.id && row.installed))
        .map((own) => ({ ...own, installed: own.version }))
      return [...listed, ...orphans].sort((a, b) => a.name.localeCompare(b.name))
    },
  )
  const [working, setWorking] = createSignal<string>()
  const [error, setError] = createSignal<unknown>()

  const act = async (row: Row, action: () => Promise<unknown>) => {
    setWorking(`${row.repositoryId}/${row.id}`)
    setError(undefined)
    try {
      await action()
      await refetch()
    } catch (failure) {
      setError(failure)
    } finally {
      setWorking(undefined)
    }
  }

  return (
    <>
      <Show when={error()}>
        <div class="mb-6">
          <Failure error={error()} />
        </div>
      </Show>
      <Switch>
        <Match when={rows.error}>
          <Failure error={rows.error} />
        </Match>
        <Match when={rows()}>
          {(list) => (
            <Show
              when={list().length > 0}
              fallback={
                <p class="text-[15px] text-muted-foreground">
                  {props.account.user.role === "admin"
                    ? "No sites to add yet. Add an extension repository in the admin panel, and its sites show up here."
                    : "No sites to add yet. Your server's admin adds the repositories they come from."}
                </p>
              }
            >
              <ul class="divide-y border-y">
                <For each={list()}>
                  {(row) => {
                    const busy = () => working() === `${row.repositoryId}/${row.id}`
                    const update = () => row.installed !== null && row.installed !== row.version
                    return (
                      <li class="flex items-center gap-4 py-4">
                        <div class="min-w-0 flex-1">
                          <p class="flex items-center gap-2 text-[17px]">
                            <span class="truncate">{row.name}</span>
                            <Show when={row.installed}>
                              <Badge variant="success">Added</Badge>
                            </Show>
                          </p>
                          <p class="truncate text-[13px] text-muted-foreground">
                            {[
                              row.sites.map(siteHost).join(", "),
                              row.formats.map((format) => formatNames[format]).join(", "),
                              `Version ${row.installed ?? row.version}`,
                            ].join(" · ")}
                          </p>
                        </div>
                        <div class="flex shrink-0 gap-2">
                          <Show when={busy()}>
                            <Spinner class="size-4 self-center text-link" />
                          </Show>
                          <Switch>
                            <Match when={!row.installed}>
                              <Button
                                size="sm"
                                disabled={working() !== undefined}
                                onClick={() =>
                                  void act(row, () =>
                                    installExtension(props.account, row.id, row.repositoryId),
                                  )
                                }
                              >
                                Add
                              </Button>
                            </Match>
                            <Match when={true}>
                              <Show when={update()}>
                                <Button
                                  size="sm"
                                  disabled={working() !== undefined}
                                  onClick={() =>
                                    void act(row, () =>
                                      installExtension(props.account, row.id, row.repositoryId),
                                    )
                                  }
                                >
                                  Update to {row.version}
                                </Button>
                              </Show>
                              <Button
                                size="sm"
                                variant="outline"
                                disabled={working() !== undefined}
                                onClick={() =>
                                  void act(row, () => uninstallExtension(props.account, row.id))
                                }
                              >
                                Remove
                              </Button>
                            </Match>
                          </Switch>
                        </div>
                      </li>
                    )
                  }}
                </For>
              </ul>
            </Show>
          )}
        </Match>
        <Match when={true}>
          <div class="divide-y border-y" aria-hidden="true">
            <For each={[0, 1, 2]}>
              {() => (
                <div class="grid gap-2 py-4">
                  <Skeleton class="h-4 w-44" />
                  <Skeleton class="h-3 w-64" />
                </div>
              )}
            </For>
          </div>
        </Match>
      </Switch>
    </>
  )
}
