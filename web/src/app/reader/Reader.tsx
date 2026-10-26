import { Match, Switch, createResource } from "solid-js"
import { Link, useParams } from "@tanstack/solid-router"
import { AlertCircle, Spinner } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { buttonVariants } from "../../components/ui/button.tsx"
import { accountByKey } from "../accounts.ts"
import { comicFormats, pages, progress, publication } from "../client.ts"
import { ComicReader } from "./ComicReader.tsx"

/** A publication open full screen, in the reader its format needs. */
export function Reader() {
  const params = useParams({ from: "/read/$server/$publicationId" })
  const account = () => accountByKey(params().server)
  const id = () => Number(params().publicationId)

  const [opened] = createResource(
    () => {
      const current = account()
      return current && !current.expired && Number.isInteger(id())
        ? { account: current, id: id() }
        : undefined
    },
    async ({ account, id }) => {
      const detail = await publication(account, id)
      const [pageList, saved] = await Promise.all([
        comicFormats.includes(detail.format) ? pages(account, id) : Promise.resolve([]),
        progress(account, id),
      ])
      return { account, detail, pages: pageList, progress: saved }
    },
  )

  return (
    <div class="fixed inset-0 bg-background text-foreground">
      <Switch>
        <Match when={!account() || account()?.expired}>
          <Message text="Sign in to this book's server to read it." />
        </Match>
        <Match when={opened.error}>
          <Message
            text={
              opened.error instanceof Error ? opened.error.message : "This book couldn't be opened."
            }
          />
        </Match>
        <Match when={opened()}>
          {(book) => (
            <Switch>
              <Match when={comicFormats.includes(book().detail.format)}>
                <ComicReader
                  account={book().account}
                  publication={book().detail}
                  pages={book().pages}
                  progress={book().progress}
                />
              </Match>
              <Match when={true}>
                <Message text="Books open on the web in a later version. Comics open now." />
              </Match>
            </Switch>
          )}
        </Match>
        <Match when={true}>
          <p
            role="status"
            class="flex h-full items-center justify-center gap-2.5 text-muted-foreground"
          >
            <Spinner class="size-[18px] text-link" />
            Opening…
          </p>
        </Match>
      </Switch>
    </div>
  )
}

function Message(props: { text: string }) {
  return (
    <div class="mx-auto flex h-full max-w-md flex-col items-start justify-center gap-6 px-6">
      <Alert variant="destructive">
        <AlertCircle />
        <p>{props.text}</p>
      </Alert>
      <Link to="/" class={buttonVariants({ variant: "outline" })}>
        Back to Reading Now
      </Link>
    </div>
  )
}
