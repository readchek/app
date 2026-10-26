import { For, type JSX } from "solid-js"
import { ToggleGroup as ToggleGroupPrimitive } from "@kobalte/core/toggle-group"
import { cn } from "../../lib/cn.ts"

/** A labeled choice of one of a few options, drawn as segments. After solid-ui's toggle group. */
export function ToggleGroup<T extends string>(props: {
  class?: string
  label: string
  value: T
  options: readonly { value: T; label: JSX.Element }[]
  onChange: (value: T) => void
}) {
  return (
    <div class={cn("grid gap-2", props.class)}>
      <span class="text-sm font-semibold">{props.label}</span>
      <ToggleGroupPrimitive
        aria-label={props.label}
        value={props.value}
        // Kobalte lets a pressed segment be unpressed; a choice always has one.
        onChange={(value) => value && props.onChange(value as T)}
        class="grid auto-cols-fr grid-flow-col rounded-xl bg-muted p-1"
      >
        <For each={props.options}>
          {(option) => (
            <ToggleGroupPrimitive.Item
              value={option.value}
              class="h-9 rounded-lg px-2 text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none data-[pressed]:bg-card data-[pressed]:text-foreground data-[pressed]:shadow-sm"
            >
              {option.label}
            </ToggleGroupPrimitive.Item>
          )}
        </For>
      </ToggleGroupPrimitive>
    </div>
  )
}
