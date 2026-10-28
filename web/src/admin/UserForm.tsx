import { For, Match, Show, Switch, createSignal } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { Link, useNavigate, useParams } from "@tanstack/solid-router"
import type { Role, User } from "../api.ts"
import { AlertCircle, CheckCircle, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import { Checkbox, CheckboxLabel } from "../components/ui/checkbox.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../components/ui/dialog.tsx"
import {
  TextField,
  TextFieldDescription,
  TextFieldInput,
  TextFieldLabel,
} from "../components/ui/text-field.tsx"
import {
  RadioGroup,
  RadioGroupItem,
  RadioGroupItemDescription,
  RadioGroupItemLabel,
  RadioGroupLabel,
} from "../components/ui/radio-group.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"
import { Heading, adminSession } from "./AdminShell.tsx"
import { Section } from "./LibraryDetail.tsx"
import { createUser, deleteUser, libraries, updateUser, users } from "./api.ts"
import { ago, call, message } from "./util.ts"

export function NewUser() {
  return <UserForm />
}

export function EditUser() {
  const session = adminSession()
  const params = useParams({ from: "/admin/users/$userId" })
  const [found] = createResource(
    () => Number(params().userId),
    async (id) => {
      const user = (await call(users(session))).find((u) => u.id === id)
      if (!user) throw new Error("This person's account no longer exists.")
      return user
    },
  )
  return (
    <Switch>
      <Match when={found.error}>
        <Heading title="Person" />
        <Alert variant="destructive">
          <AlertCircle />
          <p>{message(found.error)}</p>
        </Alert>
      </Match>
      <Match when={found()}>{(user) => <UserForm user={user()} />}</Match>
      <Match when={true}>
        <div aria-busy="true" class="grid gap-3">
          <p class="sr-only" role="status">
            Loading…
          </p>
          <Skeleton class="h-10 w-48" />
        </div>
      </Match>
    </Switch>
  )
}

/** Adds a person, or changes one: their role, the libraries a reader sees, and their password. */
function UserForm(props: { user?: User }) {
  const session = adminSession()
  const navigate = useNavigate()
  const [all] = createResource(() => call(libraries(session)))
  const [role, setRole] = createSignal<Role>(props.user?.role ?? "reader")
  const [granted, setGranted] = createSignal<number[]>(props.user?.libraryIds ?? [])
  const [status, setStatus] = createSignal<{ text: string; ok: boolean }>()
  const [busy, setBusy] = createSignal<"save" | "delete">()
  const [confirming, setConfirming] = createSignal(false)

  const editing = () => props.user !== undefined
  const yourself = () => props.user?.id === session.user.id

  const grant = (id: number, on: boolean) =>
    setGranted((ids) => (on ? [...ids, id] : ids.filter((i) => i !== id)))

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    const element = event.currentTarget as HTMLFormElement
    const form = new FormData(element)
    const password = String(form.get("password") ?? "")
    setBusy("save")
    setStatus(undefined)
    try {
      // Admins see every library, so their grants aren't sent.
      const libraryIds = role() === "reader" ? granted() : []
      if (props.user) {
        await call(
          updateUser(session, props.user.id, {
            ...(yourself() ? {} : { role: role() }),
            libraryIds,
            ...(password ? { password } : {}),
          }),
        )
        element.reset()
        setStatus({
          text: password ? "Saved. The new password signed them out everywhere." : "Saved.",
          ok: true,
        })
      } else {
        await call(
          createUser(session, {
            name: String(form.get("name")).trim(),
            password,
            role: role(),
            libraryIds,
          }),
        )
        void navigate({ to: "/admin/users" })
      }
    } catch (failure) {
      setStatus({ text: message(failure), ok: false })
    } finally {
      setBusy(undefined)
    }
  }

  const remove = async () => {
    if (!props.user) return
    setBusy("delete")
    try {
      await call(deleteUser(session, props.user.id))
      setConfirming(false)
      void navigate({ to: "/admin/users" })
    } catch (failure) {
      setStatus({ text: message(failure), ok: false })
    } finally {
      setBusy(undefined)
    }
  }

  return (
    <>
      <p class="mb-3 text-sm">
        <Link to="/admin/users" class="font-semibold text-link hover:underline">
          People
        </Link>
      </p>
      <Heading
        title={props.user?.name ?? "Add a person"}
        lead={
          props.user
            ? `Joined ${ago(props.user.createdAt)}.`
            : "They sign in to the Chek app with this name and password."
        }
      />
      <form class="grid gap-8" onSubmit={submit}>
        <Show when={!editing()}>
          <div class="grid gap-4">
            <TextField name="name" required>
              <TextFieldLabel>Name</TextFieldLabel>
              <TextFieldInput autocomplete="off" autocapitalize="off" maxlength={64} />
            </TextField>
            <TextField name="password" required>
              <TextFieldLabel>Password</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="new-password" minlength={8} />
              <TextFieldDescription>
                At least 8 characters. They can change it in the app.
              </TextFieldDescription>
            </TextField>
          </div>
        </Show>

        <RadioGroup
          value={role()}
          disabled={yourself() || busy() !== undefined}
          onChange={(value) => setRole(value as Role)}
        >
          <RadioGroupLabel class="mb-1">Role</RadioGroupLabel>
          <div class="divide-y border-y">
            <RadioGroupItem value="reader">
              <RadioGroupItemLabel>Reader</RadioGroupItemLabel>
              <RadioGroupItemDescription>
                Reads the libraries you choose below.
              </RadioGroupItemDescription>
            </RadioGroupItem>
            <RadioGroupItem value="admin">
              <RadioGroupItemLabel>Admin</RadioGroupItemLabel>
              <RadioGroupItemDescription>
                Reads every library, and manages libraries, people and extensions.
              </RadioGroupItemDescription>
            </RadioGroupItem>
          </div>
          <Show when={yourself()}>
            <p class="mt-2 text-sm text-muted-foreground">Another admin can change your role.</p>
          </Show>
        </RadioGroup>

        <Show when={role() === "reader"}>
          <fieldset class="grid gap-1">
            <legend class="mb-1 text-sm font-semibold">Libraries they can read</legend>
            <Switch>
              <Match when={all()?.length === 0}>
                <p class="border-y py-4 text-[15px] text-muted-foreground">
                  No libraries yet.{" "}
                  <Link
                    to="/admin/libraries/new"
                    search={{}}
                    class="font-semibold text-link hover:underline"
                  >
                    Add one
                  </Link>{" "}
                  first.
                </p>
              </Match>
              <Match when={all()}>
                {(items) => (
                  <div class="divide-y border-y">
                    <For each={items()}>
                      {(library) => (
                        <Checkbox
                          class="py-4"
                          checked={granted().includes(library.id)}
                          onChange={(on) => grant(library.id, on)}
                        >
                          <CheckboxLabel class="font-semibold">{library.name}</CheckboxLabel>
                        </Checkbox>
                      )}
                    </For>
                  </div>
                )}
              </Match>
              <Match when={true}>
                <div class="grid gap-3 border-y py-4">
                  <Skeleton class="h-5 w-40" />
                  <Skeleton class="h-5 w-32" />
                </div>
              </Match>
            </Switch>
          </fieldset>
        </Show>

        <Show when={editing()}>
          <TextField name="password">
            <TextFieldLabel>New password</TextFieldLabel>
            <TextFieldInput type="password" autocomplete="new-password" minlength={8} />
            <TextFieldDescription>
              {yourself()
                ? "Leave empty to keep yours. Your other devices are signed out when it changes."
                : "Leave empty to keep theirs. Setting one signs them out everywhere."}
            </TextFieldDescription>
          </TextField>
        </Show>

        <Show when={status()}>
          {(shown) => (
            <Alert variant={shown().ok ? "success" : "destructive"} role="status">
              {shown().ok ? <CheckCircle /> : <AlertCircle />}
              <p>{shown().text}</p>
            </Alert>
          )}
        </Show>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <Button type="submit" class="w-full sm:w-auto sm:px-8" disabled={busy() !== undefined}>
            <Show when={busy() === "save"}>
              <Spinner />
            </Show>
            {editing() ? "Save" : "Add person"}
          </Button>
          <Link
            to="/admin/users"
            class={buttonVariants({ variant: "ghost", class: "w-full sm:w-auto" })}
          >
            {editing() ? "Back" : "Cancel"}
          </Link>
        </div>
      </form>

      <Show when={props.user && !yourself()}>
        <div class="mt-10">
          <Section title="Delete">
            <p class="text-[15px] leading-relaxed text-muted-foreground">
              Removes their account with their progress, bookmarks and extensions.
            </p>
            <Button
              variant="outline"
              class="justify-self-start text-destructive"
              onClick={() => setConfirming(true)}
            >
              Delete {props.user!.name}
            </Button>
          </Section>
        </div>
        <Dialog open={confirming()} onOpenChange={setConfirming}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Delete {props.user!.name}?</DialogTitle>
              <DialogDescription>
                They're signed out everywhere, and their progress, bookmarks and highlights are
                deleted. This can't be undone.
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
                Delete account
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </Show>
    </>
  )
}
