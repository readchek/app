import { For, Match, Show, Switch, createResource, createSignal, onMount } from "solid-js"
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
import { AlertCircle, CheckCircle, Lock, Phone, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Badge } from "../components/ui/badge.tsx"
import { Button } from "../components/ui/button.tsx"
import { Card, CardContent, CardFooter } from "../components/ui/card.tsx"
import { Checkbox } from "../components/ui/checkbox.tsx"
import { Input, Label } from "../components/ui/input.tsx"
import { RadioCard, RadioGroup, RadioGroupLabel } from "../components/ui/radio-group.tsx"
import { Separator } from "../components/ui/separator.tsx"

type Level = "everyone" | "teen" | "mature"

// `mark` is the level's badge, in the style of an age rating.
const levels: {
  id: Level
  title: string
  mark: string
  detail: string
  ratings: readonly Rating[]
}[] = [
  { id: "everyone", title: "Everyone", mark: "E", detail: "Safe series only.", ratings: ["safe"] },
  {
    id: "teen",
    title: "Teen",
    mark: "T",
    detail: "Adds suggestive series, such as fan service.",
    ratings: ["safe", "suggestive"],
  },
  {
    id: "mature",
    title: "Mature",
    mark: "18+",
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
    <Page
      title="Content"
      lead="Choose which series sources show you."
      bubble="Your shelf, your rules."
    >
      <Card>
        <Switch>
          <Match when={phase() === "opening"}>
            <CardContent class="flex items-center gap-3 py-10 text-muted-foreground sm:py-12">
              <Spinner class="size-5 text-link" />
              <p role="status">Signing in…</p>
            </CardContent>
          </Match>
          <Match when={session()}>{(current) => <Editor session={current()} />}</Match>
          <Match when={true}>
            <SignIn server={search().server} notice={notice()} />
          </Match>
        </Switch>
      </Card>
    </Page>
  )
}

function SignIn(props: { server?: string; notice: string }) {
  const [error, setError] = createSignal(props.notice)
  const [busy, setBusy] = createSignal(false)
  // The expired-link notice leads the card; later errors sit by the button.
  const opening = () => error() !== "" && error() === props.notice

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
    <>
      <CardContent class="grid gap-5">
        <Show when={opening()}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{error()}</p>
          </Alert>
        </Show>
        <div class="flex items-start gap-3 rounded-2xl bg-muted px-4 py-3.5 text-[15px] leading-snug">
          <span class="mt-px text-link [&>svg]:size-5">
            <Phone />
          </span>
          <p>
            The quickest way here is from the Chek app: open <strong>Settings</strong>, then{" "}
            <strong>Content</strong>, and tap <strong>Open in Safari</strong>.
          </p>
        </div>
        <h2 class="mt-1 text-2xl tracking-[-0.03em]">Or sign in to your server</h2>
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
          <div class="grid gap-4 sm:grid-cols-2">
            <Label>
              Name
              <Input name="name" autocomplete="username" autocapitalize="off" required />
            </Label>
            <Label>
              Password
              <Input name="password" type="password" autocomplete="current-password" required />
            </Label>
          </div>
          <Show when={error() && !opening()}>
            <Alert variant="destructive">
              <AlertCircle />
              <p>{error()}</p>
            </Alert>
          </Show>
          <Button type="submit" size="lg" class="mt-1 w-full" disabled={busy()}>
            <Show when={busy()}>
              <Spinner />
            </Show>
            Sign in
          </Button>
          <p class="text-sm text-muted-foreground">
            If you sign in to Chek with another service, open this page from the Chek app instead.
          </p>
        </form>
      </CardContent>
      <CardFooter class="flex flex-wrap items-center justify-between gap-3">
        <span>No server of your own?</span>
        <Button
          variant="outline"
          size="sm"
          disabled={busy()}
          onClick={() => void run(signInToDemo)}
        >
          Try the demo
        </Button>
      </CardFooter>
    </>
  )
}

function Editor(props: { session: Session }) {
  const [saved, { mutate }] = createResource(async () => {
    try {
      return await contentRatings(props.session)
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) await forget()
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
      setStatus({
        text: "Saved. Switch back to Chek, and it shows the change when you return.",
        saved: true,
      })
    } catch (error) {
      setStatus({ text: message(error), saved: false })
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <CardContent class="flex items-center gap-3 pb-0 sm:pb-0">
        <span
          aria-hidden="true"
          class="flex size-11 shrink-0 items-center justify-center rounded-full bg-link/10 font-display text-lg text-link uppercase"
        >
          {props.session.user.name.charAt(0)}
        </span>
        <p class="min-w-0 flex-1 leading-tight">
          <span class="sr-only">Signed in as </span>
          <span class="flex items-center gap-2 font-semibold">
            <span class="truncate">{props.session.user.name}</span>
            <Show when={demo()}>
              <Badge variant="butter">Demo</Badge>
            </Show>
          </span>
          <span class="sr-only"> on </span>
          <span class="block truncate text-sm text-muted-foreground">
            {new URL(props.session.server).host}
          </span>
        </p>
        <Button variant="ghost" size="sm" onClick={() => void forget()}>
          Sign out
        </Button>
      </CardContent>
      <Separator class="mx-5 mt-5 sm:mx-7 sm:mt-6" />
      <CardContent>
        <Switch>
          <Match when={saved.error}>
            <Alert variant="destructive">
              <AlertCircle />
              <p>{message(saved.error)}</p>
            </Alert>
          </Match>
          <Match when={saved()}>
            {(chosen) => (
              <form class="grid gap-5" onSubmit={save}>
                <RadioGroup
                  value={current() ?? ""}
                  disabled={demo() || busy()}
                  onChange={(value) => {
                    setChoice(value as Level)
                    setStatus(undefined)
                  }}
                >
                  <RadioGroupLabel class="mb-1">Series that sources show you</RadioGroupLabel>
                  <For each={levels}>
                    {(level) => (
                      <RadioCard
                        value={level.id}
                        title={level.title}
                        description={level.detail}
                        leading={
                          <span
                            aria-hidden="true"
                            class={`flex size-11 shrink-0 items-center justify-center rounded-xl font-display tracking-[-0.03em] transition-colors group-data-[checked]:bg-link group-data-[checked]:text-primary-foreground ${level.id === "mature" ? "bg-butter text-[15px] text-butter-foreground" : "bg-muted text-lg"}`}
                          >
                            {level.mark}
                          </span>
                        }
                      />
                    )}
                  </For>
                </RadioGroup>
                <Show when={!current()}>
                  <p class="text-[15px] text-muted-foreground">
                    You see {chosen().join(", ")} series, chosen in an earlier version of Chek.
                  </p>
                </Show>
                <Show when={choice() === "mature" && changed()}>
                  <div class="rounded-2xl bg-butter px-4 py-3.5 text-butter-foreground">
                    <Checkbox checked={adult()} onChange={setAdult}>
                      I'm 18 or older, and I want to see adult content.
                    </Checkbox>
                  </div>
                </Show>
                <Show
                  when={!demo()}
                  fallback={
                    <Alert variant="note" role="note">
                      <Lock />
                      <p>
                        The demo always shows safe and suggestive series. Sign in to your own Chek
                        server to change this.
                      </p>
                    </Alert>
                  }
                >
                  <Button type="submit" size="lg" class="w-full" disabled={!canSave()}>
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
            <div class="grid gap-2.5" aria-busy="true">
              <p class="sr-only" role="status">
                Loading…
              </p>
              <For each={levels}>
                {() => <div class="h-[74px] animate-pulse rounded-2xl bg-muted sm:h-[78px]" />}
              </For>
            </div>
          </Match>
        </Switch>
      </CardContent>
    </>
  )
}
