import { type JSX, Match, Show, Switch, createEffect, createSignal, onCleanup } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { Link, useNavigate, useParams } from "@tanstack/solid-router"
import { AlertCircle, CheckCircle, Spinner } from "../components/icons.tsx"
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
import { TextField, TextFieldInput, TextFieldLabel } from "../components/ui/text-field.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"
import { Heading, adminSession } from "./AdminShell.tsx"
import { SCAN_POLL_MS, ScanStatus, origin } from "./Libraries.tsx"
import { deleteLibrary, library, renameLibrary, scanLibrary, users } from "./api.ts"
import { ago, call, count, message } from "./util.ts"

/** A titled part of a screen, set apart by a rule like the settings page's lists. */
export function Section(props: { title: string; children: JSX.Element }) {
  return (
    <section class="grid gap-3">
      <h2 class="text-[22px] leading-tight tracking-[-0.03em]">{props.title}</h2>
      {props.children}
    </section>
  )
}

export function LibraryDetail() {
  const session = adminSession()
  const navigate = useNavigate()
  const params = useParams({ from: "/admin/libraries/$libraryId" })
  const id = () => Number(params().libraryId)
  const [shown, { refetch, mutate }] = createResource(id, (id) => call(library(session, id)))
  const [people] = createResource(() => call(users(session)))
  const [status, setStatus] = createSignal<{ text: string; ok: boolean }>()
  const [busy, setBusy] = createSignal<"scan" | "rename" | "delete">()
  const [confirming, setConfirming] = createSignal(false)

  createEffect(() => {
    if (shown.latest?.scan.status !== "scanning") return
    const timer = setInterval(() => void refetch(), SCAN_POLL_MS)
    onCleanup(() => clearInterval(timer))
  })

  const readers = () =>
    people()?.filter((p) => p.role === "reader" && p.libraryIds.includes(id())) ?? []

  const run = async (what: "scan" | "rename" | "delete", action: () => Promise<void>) => {
    setBusy(what)
    setStatus(undefined)
    try {
      await action()
    } catch (failure) {
      setStatus({ text: message(failure), ok: false })
    } finally {
      setBusy(undefined)
    }
  }

  const scan = () =>
    run("scan", async () => {
      await call(scanLibrary(session, id()))
      await refetch()
    })

  const rename = (event: SubmitEvent) => {
    event.preventDefault()
    const name = String(new FormData(event.currentTarget as HTMLFormElement).get("name")).trim()
    void run("rename", async () => {
      mutate(await call(renameLibrary(session, id(), name)))
      setStatus({ text: "Renamed.", ok: true })
    })
  }

  const remove = () =>
    run("delete", async () => {
      await call(deleteLibrary(session, id()))
      setConfirming(false)
      void navigate({ to: "/admin/libraries" })
    })

  return (
    <Switch>
      <Match when={shown.error}>
        <Heading title="Library" />
        <Alert variant="destructive">
          <AlertCircle />
          <p>{message(shown.error)}</p>
        </Alert>
      </Match>
      <Match when={shown.latest}>
        {(current) => (
          <>
            <p class="mb-3 text-sm">
              <Link to="/admin/libraries" class="font-semibold text-link hover:underline">
                Libraries
              </Link>
            </p>
            <Heading title={current().name} lead={origin(current())} />
            <div class="grid gap-10">
              <Section title="Scan">
                <div class="flex flex-wrap items-center justify-between gap-4">
                  <div class="grid gap-1">
                    <ScanStatus library={current()} />
                    <Show when={current().scan.status === "scanning"}>
                      <span class="text-[15px] text-muted-foreground">
                        Books show up in Chek as they're found.
                      </span>
                    </Show>
                    <Show when={!current().scan.finishedAt && current().scan.status !== "scanning"}>
                      <span class="text-[15px] text-muted-foreground">Not scanned yet.</span>
                    </Show>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={busy() !== undefined || current().scan.status === "scanning"}
                    onClick={() => void scan()}
                  >
                    <Show when={busy() === "scan"}>
                      <Spinner />
                    </Show>
                    Scan now
                  </Button>
                </div>
                <Show when={current().scan.status === "failed" && current().scan.error}>
                  {(error) => (
                    <Alert variant="destructive">
                      <AlertCircle />
                      <p>{error()}</p>
                    </Alert>
                  )}
                </Show>
                <p class="text-sm text-muted-foreground">
                  {current().kind === "folder"
                    ? "Folders are scanned when the server starts and whenever you ask. Unchanged files are skipped."
                    : "Sources sync when the server starts, every hour, and whenever you ask."}
                </p>
              </Section>

              <Section title="Who can read it">
                <p class="text-[15px] leading-relaxed text-muted-foreground">
                  Every admin, and{" "}
                  <Show when={readers().length > 0} fallback="no readers yet">
                    {count(readers().length, "reader", "readers")}:{" "}
                    <span class="text-foreground">
                      {readers()
                        .map((r) => r.name)
                        .join(", ")}
                    </span>
                  </Show>
                  .{" "}
                  <Link to="/admin/users" class="font-semibold text-link hover:underline">
                    Choose in People
                  </Link>
                </p>
              </Section>

              <Section title="Name">
                <form class="flex flex-col gap-3 sm:flex-row" onSubmit={rename}>
                  <TextField name="name" defaultValue={current().name} required class="flex-1">
                    <TextFieldLabel class="sr-only">Name</TextFieldLabel>
                    <TextFieldInput />
                  </TextField>
                  <Button
                    type="submit"
                    variant="outline"
                    class="h-12"
                    disabled={busy() !== undefined}
                  >
                    <Show when={busy() === "rename"}>
                      <Spinner />
                    </Show>
                    Rename
                  </Button>
                </form>
              </Section>

              <Show when={status()}>
                {(shownStatus) => (
                  <Alert variant={shownStatus().ok ? "success" : "destructive"} role="status">
                    {shownStatus().ok ? <CheckCircle /> : <AlertCircle />}
                    <p>{shownStatus().text}</p>
                  </Alert>
                )}
              </Show>

              <Section title="Delete">
                <p class="text-[15px] leading-relaxed text-muted-foreground">
                  Removes the library from Chek, with everyone's progress and bookmarks in it.{" "}
                  {current().kind === "folder"
                    ? "The files stay in the folder."
                    : "The books stay on the server they came from."}{" "}
                  Added {ago(current().createdAt)}.
                </p>
                <Button
                  variant="outline"
                  class="justify-self-start text-destructive"
                  onClick={() => setConfirming(true)}
                >
                  Delete library
                </Button>
              </Section>
            </div>
            <Dialog open={confirming()} onOpenChange={setConfirming}>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Delete {current().name}?</DialogTitle>
                  <DialogDescription>
                    Everyone loses their progress, bookmarks and highlights in it. Adding it again
                    finds the books, but not those. This can't be undone.
                  </DialogDescription>
                </DialogHeader>
                <Show when={status() && !status()!.ok}>
                  <Alert variant="destructive">
                    <AlertCircle />
                    <p>{status()!.text}</p>
                  </Alert>
                </Show>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setConfirming(false)}>
                    Cancel
                  </Button>
                  <Button
                    variant="destructive"
                    disabled={busy() !== undefined}
                    onClick={() => void remove()}
                  >
                    <Show when={busy() === "delete"}>
                      <Spinner />
                    </Show>
                    Delete library
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </>
        )}
      </Match>
      <Match when={true}>
        <div aria-busy="true" class="grid gap-3">
          <p class="sr-only" role="status">
            Loading…
          </p>
          <Skeleton class="h-10 w-56" />
          <Skeleton class="h-5 w-72" />
        </div>
      </Match>
    </Switch>
  )
}
