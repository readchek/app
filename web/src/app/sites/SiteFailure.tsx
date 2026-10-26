import { Show, createSignal } from "solid-js"
import { ApiError } from "../../api.ts"
import { AlertCircle } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { Button } from "../../components/ui/button.tsx"
import type { Account } from "../accounts.ts"
import type { SiteInfo } from "./data.ts"
import { Verify } from "./Verify.tsx"

/**
 * Why a site didn't answer, with a way to try again. A site that checks
 * for a person, through an extension that can use the server's browser,
 * is offered the check too.
 */
export function SiteFailure(props: {
  account: Account
  site: SiteInfo | undefined
  error: unknown
  retry: () => void
}) {
  const [verifying, setVerifying] = createSignal(false)
  const sourceFailed = () => props.error instanceof ApiError && props.error.code === "source_failed"
  const canVerify = () =>
    sourceFailed() && (props.site?.capabilities.includes("browser-session") ?? false)

  return (
    <div class="grid max-w-2xl gap-4">
      <Alert variant="destructive">
        <AlertCircle />
        <div class="grid gap-1">
          <p>
            {sourceFailed()
              ? "The site didn't answer as expected. It may be down, or checking for a person."
              : props.error instanceof Error
                ? props.error.message
                : "Something went wrong. Try again."}
          </p>
          <Show when={sourceFailed() && props.error instanceof Error}>
            <p class="text-sm opacity-80">{(props.error as Error).message}</p>
          </Show>
        </div>
      </Alert>
      <div class="flex flex-wrap gap-3">
        <Button variant="outline" onClick={() => props.retry()}>
          Try again
        </Button>
        <Show when={canVerify()}>
          <Button onClick={() => setVerifying(true)}>Check you're a person</Button>
        </Show>
      </div>
      <Show when={props.site && canVerify()}>
        <Verify
          account={props.account}
          extensionId={props.site!.id}
          sites={props.site!.sites}
          open={verifying()}
          onClose={(verified) => {
            setVerifying(false)
            if (verified) props.retry()
          }}
        />
      </Show>
    </div>
  )
}
