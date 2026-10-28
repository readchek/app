import { For, Match, Show, Switch, createSignal, onMount } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { useSearch } from "@tanstack/solid-router"
import {
  ApiError,
  type Rating,
  type Session,
  contentRatings,
  openLink,
  ratings,
  serverAddress,
  setContentRatings,
  signIn,
  signInToDemo,
} from "../api.ts"
import { forget, remember, session } from "../session.ts"
import { Page } from "../components/Page.tsx"
import { AlertCircle, CheckCircle, Lock, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Badge } from "../components/ui/badge.tsx"
import { Button } from "../components/ui/button.tsx"
import { Checkbox } from "../components/ui/checkbox.tsx"
import { Input, Label } from "../components/ui/input.tsx"
import { RadioGroup, RadioGroupLabel, RadioRow } from "../components/ui/radio-group.tsx"

type Level = "everyone" | "teen" | "mature"

const levels: { id: Level; title: string; detail: string; ratings: readonly Rating[] }[] = [
  { id: "everyone", title: "Everyone", detail: "Safe series only.", ratings: ["safe"] },
  {
    id: "teen",
    title: "Teen",
    detail: "Adds suggestive series, such as fan service.",
    ratings: ["safe", "suggestive"],
  },
  {
    id: "mature",
    title: "Mature",
    detail: "Adds erotica and pornographic series. For adults only.",
    ratings,
  },
]

function levelOf(chosen: readonly Rating[]): Level | undefined {
  return levels.find(
    (level) =>
      level.ratings.length === chosen.length && level.ratings.every((r) => chosen.includes(r)),
  )?.id
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : "Something went wrong. Try again."
}

export function ContentSettings() {
  const search = useSearch({ from: "/settings/content" })
  const [phase, setPhase] = createSignal<"opening" | "ready">("opening")
  const [notice, setNotice] = createSignal("")

  onMount(async () => {
    // The app's link carries a one-time code in the fragment. It's taken
    // out of the address at once, so it isn't left in history.
    const code = new URLSearchParams(location.hash.slice(1)).get("code")
    const server = search().server
    if (code) history.replaceState(history.state, "", location.pathname + location.search)
    const current = session()
    if (code && server) {
      try {
        const address = serverAddress(server)
        if (current) await forget()
        remember(await openLink(address, code))
      } catch (error) {
        setNotice(
          error instanceof ApiError && error.status === 400
            ? "This link has expired or was already used. Open it again from the Chek app, or sign in below."
            : message(error),
        )
      }
    } else if (current && server && current.server !== server.replace(/\/+$/, "")) {
      // Opened for a different server than the one this tab is signed in to.
      await forget()
    }
    setPhase("ready")
  })

  return (
    <Page title="Content" lead="Choose which series sources show you.">
      <Switch>
        <Match when={phase() === "opening"}>
          <p role="status" class="flex items-center gap-2.5 text-muted-foreground">
            <Spinner class="size-[18px] text-link" />
            Signing in…
          </p>
        </Match>
        <Match when={session()}>
          {(current) => (
            <div class="grid gap-8">
              <p class="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-[15px] text-muted-foreground">
                <span>
                  Signed in as{" "}
                  <strong class="font-semibold text-foreground">{current().user.name}</strong> on{" "}
                  {new URL(current().server).host}.
                </span>
                <Show when={current().user.demo}>
                  <Badge variant="butter">Demo</Badge>
                </Show>
                <Button variant="link" size="inline" onClick={() => void forget()}>
                  Sign out
                </Button>
              </p>
              <ContentRatingsForm
                session={current()}
                savedText="Saved. Switch back to Chek, and it shows the change when you return."
                onUnauthorized={() => void forget()}
              />
            </div>
          )}
        </Match>
        <Match when={true}>
          <SignIn server={search().server} notice={notice()} />
        </Match>
      </Switch>
    </Page>
  )
}

function SignIn(props: { server?: string; notice: string }) {
  const [error, setError] = createSignal(props.notice)
  const [busy, setBusy] = createSignal(false)

  const run = async (signingIn: () => Promise<Session>) => {
    setBusy(true)
    setError("")
    try {
      remember(await signingIn())
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  const submit = (event: SubmitEvent) => {
    event.preventDefault()
    const form = new FormData(event.currentTarget as HTMLFormElement)
    void run(() =>
      signIn(
        serverAddress(String(form.get("server"))),
        String(form.get("name")).trim(),
        String(form.get("password")),
      ),
    )
  }

  return (
    <div class="grid gap-8">
      <p class="text-[15px] leading-relaxed text-muted-foreground">
        The quickest way here is from the Chek app: open Settings, then Content, and tap Open in
        Safari.
      </p>
      <form class="grid gap-4" onSubmit={submit}>
        <Label>
          Server address
          <Input
            name="server"
            value={props.server ?? ""}
            placeholder="chek.example.com"
            autocomplete="url"
            inputmode="url"
            autocapitalize="off"
            spellcheck={false}
            required
          />
        </Label>
        <Label>
          Name
          <Input name="name" autocomplete="username" autocapitalize="off" required />
        </Label>
        <Label>
          Password
          <Input name="password" type="password" autocomplete="current-password" required />
        </Label>
        <Show when={error()}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{error()}</p>
          </Alert>
        </Show>
        <Button type="submit" class="mt-2 w-full sm:w-auto sm:justify-self-start" disabled={busy()}>
          <Show when={busy()}>
            <Spinner />
          </Show>
          Sign in
        </Button>
        <p class="text-sm text-muted-foreground">
          If you sign in to Chek with another service, open this page from the Chek app instead.
        </p>
      </form>
      <p class="border-t pt-6 text-[15px] text-muted-foreground">
        No server of your own?{" "}
        <Button
          variant="link"
          size="inline"
          disabled={busy()}
          onClick={() => void run(signInToDemo)}
        >
          Try the demo
        </Button>
      </p>
    </div>
  )
}

/**
 * Chooses which series sources show: Everyone, Teen, or Mature after
 * confirming an adult's age. Mature can be turned on only on the web,
 * under App Review Guideline 1.2.
 */
export function ContentRatingsForm(props: {
  session: Session
  /** What to say once saved. */
  savedText: string
  onUnauthorized: () => void
}) {
  const [saved, { mutate }] = createResource(async () => {
    try {
      return await contentRatings(props.session)
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) props.onUnauthorized()
      throw error
    }
  })
  const [choice, setChoice] = createSignal<Level>()
  const [adult, setAdult] = createSignal(false)
  const [status, setStatus] = createSignal<{ text: string; saved: boolean }>()
  const [busy, setBusy] = createSignal(false)

  const current = () => choice() ?? levelOf(saved() ?? [])
  const demo = () => props.session.user.demo === true
  const changed = () => choice() !== undefined && choice() !== levelOf(saved() ?? [])
  const canSave = () => changed() && !busy() && (choice() !== "mature" || adult())

  const save = async (event: SubmitEvent) => {
    event.preventDefault()
    const level = levels.find((l) => l.id === choice())
    if (!level) return
    setBusy(true)
    setStatus(undefined)
    try {
      mutate(await setContentRatings(props.session, [...level.ratings]))
      setChoice(undefined)
      setAdult(false)
      setStatus({ text: props.savedText, saved: true })
    } catch (error) {
      setStatus({ text: message(error), saved: false })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <Switch>
        <Match when={saved.error}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{message(saved.error)}</p>
          </Alert>
        </Match>
        <Match when={saved()}>
          {(chosen) => (
            <form class="grid gap-6" onSubmit={save}>
              <RadioGroup
                value={current() ?? ""}
                disabled={demo() || busy()}
                onChange={(value) => {
                  setChoice(value as Level)
                  setStatus(undefined)
                }}
              >
                <RadioGroupLabel class="mb-1">Series that sources show you</RadioGroupLabel>
                <div class="divide-y border-y">
                  <For each={levels}>
                    {(level) => (
                      <RadioRow
                        value={level.id}
                        title={
                          <>
                            {level.title}
                            <Show when={level.id === "mature"}>
                              <Badge variant="butter">18+</Badge>
                            </Show>
                          </>
                        }
                        description={level.detail}
                      />
                    )}
                  </For>
                </div>
              </RadioGroup>
              <Show when={!current()}>
                <p class="text-[15px] text-muted-foreground">
                  You see {chosen().join(", ")} series, chosen in an earlier version of Chek.
                </p>
              </Show>
              <Show when={choice() === "mature" && changed()}>
                <Checkbox checked={adult()} onChange={setAdult}>
                  I'm 18 or older, and I want to see adult content.
                </Checkbox>
              </Show>
              <Show
                when={!demo()}
                fallback={
                  <Alert role="note">
                    <Lock />
                    <p>
                      The demo always shows safe and suggestive series. Sign in to your own Chek
                      server to change this.
                    </p>
                  </Alert>
                }
              >
                <Button
                  type="submit"
                  class="w-full sm:w-auto sm:justify-self-start sm:px-8"
                  disabled={!canSave()}
                >
                  <Show when={busy()}>
                    <Spinner />
                  </Show>
                  Save
                </Button>
              </Show>
              <Show when={status()}>
                {(shown) => (
                  <Alert variant={shown().saved ? "success" : "destructive"} role="status">
                    {shown().saved ? <CheckCircle /> : <AlertCircle />}
                    <p>{shown().text}</p>
                  </Alert>
                )}
              </Show>
            </form>
          )}
        </Match>
        <Match when={true}>
          <div aria-busy="true">
            <p class="sr-only" role="status">
              Loading…
            </p>
            <div class="h-5 w-48 animate-pulse rounded bg-muted" />
            <div class="mt-3 divide-y border-y">
              <For each={levels}>
                {() => (
                  <div class="flex gap-3.5 py-4">
                    <div class="size-5 animate-pulse rounded-full bg-muted" />
                    <div class="grid flex-1 gap-2">
                      <div class="h-4 w-24 animate-pulse rounded bg-muted" />
                      <div class="h-4 w-56 animate-pulse rounded bg-muted" />
                    </div>
                  </div>
                )}
              </For>
            </div>
          </div>
        </Match>
      </Switch>
    </div>
  )
}
