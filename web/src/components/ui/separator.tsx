import { type JSX, Show } from "solid-js"
import { cn } from "../../lib/cn.ts"

/** A rule across the card, with an optional word such as "or" in the middle. */
export function Separator(props: { class?: string; children?: JSX.Element }) {
  return (
    <div class={cn("flex items-center gap-3 text-sm text-muted-foreground", props.class)}>
      <span class="h-px flex-1 bg-border" />
      <Show when={props.children}>
        {props.children}
        <span class="h-px flex-1 bg-border" />
      </Show>
    </div>
  )
}
