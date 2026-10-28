import { For, type JSX } from "solid-js"
import { cn } from "../lib/cn.ts"
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group.tsx"

/** A labeled choice of one of a few options, drawn as solid-ui's toggle group in segments. */
export function Choice<T extends string>(props: {
  class?: string
  label: string
  value: T
  options: readonly { value: T; label: JSX.Element }[]
  onChange: (value: T) => void
}) {
  return (
    <div class={cn("grid gap-2", props.class)}>
      <span class="text-sm font-semibold">{props.label}</span>
      <ToggleGroup
        variant="segmented"
        aria-label={props.label}
        value={props.value}
        // Kobalte lets a pressed segment be unpressed; a choice always has one.
        onChange={(value: string | null) => value && props.onChange(value as T)}
      >
        <For each={props.options}>
          {(option) => (
            <ToggleGroupItem value={option.value} class="px-2">
              {option.label}
            </ToggleGroupItem>
          )}
        </For>
      </ToggleGroup>
    </div>
  )
}
