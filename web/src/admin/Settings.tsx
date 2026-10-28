import { Show, createSignal } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { bundled } from "../api.ts"
import { forget } from "../session.ts"
import { AlertCircle, ArrowUpRight, CheckCircle, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import { TextField, TextFieldInput, TextFieldLabel } from "../components/ui/text-field.tsx"
import { Heading, adminSession } from "./AdminShell.tsx"
import { Section } from "./LibraryDetail.tsx"
import { changePassword, serverInfo } from "./api.ts"
import { call, message } from "./util.ts"

export function Settings() {
  const session = adminSession()
  const [info] = createResource(() => serverInfo(session.server))
  const [status, setStatus] = createSignal<{ text: string; ok: boolean }>()
  const [busy, setBusy] = createSignal(false)

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    const element = event.currentTarget as HTMLFormElement
    const form = new FormData(element)
    const next = String(form.get("next"))
    if (next !== String(form.get("confirm"))) {
      setStatus({ text: "The new passwords don't match.", ok: false })
      return
    }
    setBusy(true)
    setStatus(undefined)
    try {
      await call(changePassword(session, String(form.get("current")), next))
      element.reset()
      setStatus({ text: "Changed. Your other devices were signed out.", ok: true })
    } catch (failure) {
      setStatus({ text: message(failure), ok: false })
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <Heading title="Settings" lead="This server, and your own account." />
      <div class="grid gap-10">
        <Section title="Server">
          <dl class="divide-y border-y text-[15px]">
            <div class="flex justify-between gap-4 py-3">
              <dt class="text-muted-foreground">Address</dt>
              <dd class="truncate font-semibold" dir="ltr">
                {new URL(session.server).host}
              </dd>
            </div>
            <div class="flex justify-between gap-4 py-3">
              <dt class="text-muted-foreground">Version</dt>
              <dd class="font-semibold">{info()?.version ?? "…"}</dd>
            </div>
          </dl>
          <p class="text-sm leading-relaxed text-muted-foreground">
            Everything else, such as sign-in providers, uploads and the outbound proxy, is set with
            environment variables when the server starts.
          </p>
          <a
            href="https://docs.chek.page/self-hosting/configuration/"
            class={buttonVariants({ variant: "outline", size: "sm", class: "justify-self-start" })}
          >
            Configuration reference
            <ArrowUpRight />
          </a>
        </Section>

        <Section title="Your password">
          <form class="grid gap-4" onSubmit={submit}>
            <TextField name="current" required>
              <TextFieldLabel>Current password</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="current-password" />
            </TextField>
            <TextField name="next" required>
              <TextFieldLabel>New password</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="new-password" minlength={8} />
            </TextField>
            <TextField name="confirm" required>
              <TextFieldLabel>New password again</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="new-password" />
            </TextField>
            <Show when={status()}>
              {(shown) => (
                <Alert variant={shown().ok ? "success" : "destructive"} role="status">
                  {shown().ok ? <CheckCircle /> : <AlertCircle />}
                  <p>{shown().text}</p>
                </Alert>
              )}
            </Show>
            <Button
              type="submit"
              variant="outline"
              class="mt-2 w-full sm:w-auto sm:justify-self-start sm:px-8"
              disabled={busy()}
            >
              <Show when={busy()}>
                <Spinner />
              </Show>
              Change password
            </Button>
          </form>
        </Section>

        <Section title="Signed in">
          <p class="flex flex-wrap items-center gap-x-1.5 text-[15px] text-muted-foreground">
            <span>
              As <strong class="font-semibold text-foreground">{session.user.name}</strong>
              {bundled ? "." : ` on ${new URL(session.server).host}.`}
            </span>
            <Button variant="link" size="inline" onClick={() => void forget()}>
              Sign out
            </Button>
          </p>
        </Section>
      </div>
    </>
  )
}
