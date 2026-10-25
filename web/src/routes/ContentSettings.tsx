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
    <section>
      <h1>Content</h1>
      <Switch>
        <Match when={phase() === "opening"}>
          <p class="muted" role="status">
            Signing in…
          </p>
        </Match>
        <Match when={session()}>{(current) => <Editor session={current()} />}</Match>
        <Match when={true}>
          <SignIn server={search().server} notice={notice()} />
        </Match>
      </Switch>
    </section>
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
    <>
      <p>
        Choose which series sources show you. The quickest way here is from the Chek app: open
        Settings, then Content, and tap Open in Safari.
      </p>
      <form class="stack" onSubmit={submit}>
        <label>
          Server address
          <input
            name="server"
            value={props.server ?? ""}
            placeholder="chek.example.com"
            autocomplete="url"
            inputmode="url"
            autocapitalize="off"
            spellcheck={false}
            required
          />
        </label>
        <label>
          Name
          <input name="name" autocomplete="username" autocapitalize="off" required />
        </label>
        <label>
          Password
          <input name="password" type="password" autocomplete="current-password" required />
        </label>
        <button class="primary" disabled={busy()}>
          Sign in
        </button>
      </form>
      <p class="muted">
        If you sign in to Chek with another service, open this page from the Chek app instead.
      </p>
      <Show when={error()}>
        <p class="error" role="alert">
          {error()}
        </p>
      </Show>
      <hr />
      <p class="muted">No server of your own?</p>
      <button disabled={busy()} onClick={() => void run(signInToDemo)}>
        Try the demo
      </button>
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
  const [status, setStatus] = createSignal("")
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
    setStatus("")
    try {
      mutate(await setContentRatings(props.session, [...level.ratings]))
      setChoice(undefined)
      setAdult(false)
      setStatus("Saved. Switch back to Chek, and it shows the change when you return.")
    } catch (error) {
      setStatus(message(error))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <p class="muted">
        Signed in as <strong>{props.session.user.name}</strong> on{" "}
        {new URL(props.session.server).host}.{" "}
        <button class="link" onClick={() => void forget()}>
          Sign out
        </button>
      </p>
      <Switch>
        <Match when={saved.error}>
          <p class="error" role="alert">
            {message(saved.error)}
          </p>
        </Match>
        <Match when={saved()}>
          {(chosen) => (
            <form class="stack" onSubmit={save}>
              <fieldset disabled={demo() || busy()}>
                <legend>Series that sources show you</legend>
                <For each={levels}>
                  {(level) => (
                    <label class="option">
                      <input
                        type="radio"
                        name="level"
                        value={level.id}
                        checked={current() === level.id}
                        onChange={() => {
                          setChoice(level.id)
                          setStatus("")
                        }}
                      />
                      <span>
                        <strong>{level.title}</strong>
                        <span class="muted">{level.detail}</span>
                      </span>
                    </label>
                  )}
                </For>
                <Show when={!current()}>
                  <p class="muted">
                    You see {chosen().join(", ")} series, chosen in an earlier version of Chek.
                  </p>
                </Show>
              </fieldset>
              <Show when={choice() === "mature" && changed()}>
                <label class="option">
                  <input
                    type="checkbox"
                    checked={adult()}
                    onChange={(event) => setAdult(event.currentTarget.checked)}
                  />
                  <span>I'm 18 or older, and I want to see adult content.</span>
                </label>
              </Show>
              <Show
                when={!demo()}
                fallback={
                  <p class="muted">
                    The demo always shows safe and suggestive series. Sign in to your own Chek
                    server to change this.
                  </p>
                }
              >
                <button class="primary" disabled={!canSave()}>
                  Save
                </button>
              </Show>
              <Show when={status()}>
                <p role="status">{status()}</p>
              </Show>
            </form>
          )}
        </Match>
        <Match when={true}>
          <p class="muted" role="status">
            Loading…
          </p>
        </Match>
      </Switch>
    </>
  )
}
