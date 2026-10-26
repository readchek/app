import { Match, Show, Switch, createResource, createSignal } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { AlertCircle, Bookmark, Spinner } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../../components/ui/dialog.tsx"
import { Input } from "../../components/ui/input.tsx"
import { Select } from "../../components/ui/select.tsx"
import { type Account, accountKey } from "../accounts.ts"
import { type Library, libraries, search } from "../client.ts"
import { type RemoteSeries, addExtensionLibrary, followSeries } from "./api.ts"
import { siteInfo } from "./data.ts"

/**
 * Following a series, for a server's admin: the series goes into a library
 * that runs on the site's extension, where the server keeps its chapters
 * up to date and keeps everyone's place in them, on every device.
 */
export function Follow(props: { account: Account; extensionId: string; series: RemoteSeries }) {
  const [open, setOpen] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [error, setError] = createSignal<string>()
  const [chosen, setChosen] = createSignal<number>()
  const [name, setName] = createSignal("")

  const [state, { refetch }] = createResource(async () => {
    const all = (await libraries(props.account)).items.filter(
      (library) =>
        library.source?.type === "extension" && library.source.extensionId === props.extensionId,
    )
    // A followed series is a series of the same title in one of them.
    for (const library of all) {
      const found = await search(props.account, {
        q: props.series.title,
        libraryId: library.id,
        limit: 20,
      }).catch(() => undefined)
      const match = found?.items.find((item) => item.series.title === props.series.title)
      if (match) return { libraries: all, following: { library, seriesId: match.series.id } }
    }
    return { libraries: all, following: undefined }
  })

  const target = (): Library | undefined =>
    state()?.libraries.find((library) => library.id === chosen()) ?? state()?.libraries[0]

  const start = async () => {
    setError(undefined)
    setChosen(undefined)
    if (!name())
      setName((await siteInfo(props.account, props.extensionId).catch(() => undefined))?.name ?? "")
    setOpen(true)
  }

  const follow = async () => {
    setBusy(true)
    setError(undefined)
    try {
      const libraryId =
        target()?.id ??
        (
          await addExtensionLibrary(
            props.account,
            name().trim() || props.series.title,
            props.extensionId,
          )
        ).id
      await followSeries(props.account, libraryId, props.series.id)
      setOpen(false)
      await refetch()
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "The series couldn't be followed.")
    } finally {
      setBusy(false)
    }
  }

  return (
    <Switch>
      <Match when={state()?.following}>
        {(following) => (
          <Link
            to="/shared/$server/series/$seriesId"
            params={{ server: accountKey(props.account), seriesId: String(following().seriesId) }}
            class={buttonVariants({ variant: "outline", class: "w-full sm:w-auto" })}
          >
            <Bookmark />
            <span class="truncate">Following in {following().library.name}</span>
          </Link>
        )}
      </Match>
      <Match when={state()}>
        {(loaded) => (
          <>
            <Button variant="outline" class="w-full sm:w-auto" onClick={() => void start()}>
              <Bookmark />
              Follow
            </Button>
            <Dialog open={open()} onOpenChange={(next) => !busy() && setOpen(next)}>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Follow {props.series.title}</DialogTitle>
                  <DialogDescription>
                    Your server adds the series to a library and keeps its chapters up to date.
                    Everyone you give the library to can read it, and their place in each chapter is
                    kept on every device.
                  </DialogDescription>
                </DialogHeader>
                <Show when={error()}>
                  <Alert variant="destructive">
                    <AlertCircle />
                    <p>{error()}</p>
                  </Alert>
                </Show>
                <Switch>
                  <Match when={loaded().libraries.length > 1}>
                    <Select
                      label="Library"
                      showLabel
                      options={loaded().libraries.map((library) => ({
                        value: String(library.id),
                        label: library.name,
                      }))}
                      value={target() && { value: String(target()!.id), label: target()!.name }}
                      onChange={(option) => setChosen(Number(option.value))}
                    />
                  </Match>
                  <Match when={loaded().libraries.length === 1}>
                    <p class="text-[15px]">
                      It goes into <span class="font-semibold">{loaded().libraries[0]!.name}</span>.
                    </p>
                  </Match>
                  <Match when={true}>
                    <div class="grid gap-2">
                      <label for="follow-library" class="text-sm font-semibold">
                        New library's name
                      </label>
                      <Input
                        id="follow-library"
                        value={name()}
                        onInput={(event) => setName(event.currentTarget.value)}
                      />
                      <p class="text-sm text-muted-foreground">
                        No library reads from this site yet, so one is made for it. Give people
                        access to it in the admin panel.
                      </p>
                    </div>
                  </Match>
                </Switch>
                <DialogFooter>
                  <Button variant="outline" disabled={busy()} onClick={() => setOpen(false)}>
                    Cancel
                  </Button>
                  <Button disabled={busy()} onClick={() => void follow()}>
                    <Show when={busy()}>
                      <Spinner class="size-4" />
                    </Show>
                    {busy() ? "Following…" : "Follow"}
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </>
        )}
      </Match>
    </Switch>
  )
}
