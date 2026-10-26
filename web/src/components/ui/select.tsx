import type { JSX } from "solid-js"
import { Select as SelectPrimitive } from "@kobalte/core/select"
import { cn } from "../../lib/cn.ts"

/** A choice of one option from a list that opens over the page. After solid-ui's select. */
export function Select<T extends { value: string; label: string }>(props: {
  class?: string
  label: string
  options: T[]
  value: T | undefined
  onChange: (option: T) => void
  /** Puts the label on screen; otherwise it's only for screen readers. */
  showLabel?: boolean
}) {
  return (
    <SelectPrimitive<T>
      class={cn("grid gap-1.5", props.class)}
      options={props.options}
      optionValue="value"
      optionTextValue="label"
      value={props.value}
      onChange={(option) => option && props.onChange(option)}
      disallowEmptySelection
      gutter={6}
      itemComponent={(item) => (
        <SelectPrimitive.Item
          item={item.item}
          class="flex cursor-pointer items-center justify-between gap-3 rounded-lg px-3 py-2 text-[15px] outline-none data-[highlighted]:bg-muted"
        >
          <SelectPrimitive.ItemLabel>{item.item.rawValue.label}</SelectPrimitive.ItemLabel>
          <SelectPrimitive.ItemIndicator class="text-link">
            <Check />
          </SelectPrimitive.ItemIndicator>
        </SelectPrimitive.Item>
      )}
    >
      <SelectPrimitive.Label class={cn("text-sm font-semibold", !props.showLabel && "sr-only")}>
        {props.label}
      </SelectPrimitive.Label>
      <SelectPrimitive.Trigger class="flex h-10 items-center justify-between gap-2 rounded-full border border-input bg-card px-4 text-sm font-semibold transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none">
        <SelectPrimitive.Value<T> class="truncate">
          {(state) => state.selectedOption().label}
        </SelectPrimitive.Value>
        <SelectPrimitive.Icon class="text-muted-foreground">
          <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
            <path
              d="m7 10 5 5 5-5"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </SelectPrimitive.Icon>
      </SelectPrimitive.Trigger>
      <SelectPrimitive.Portal>
        <SelectPrimitive.Content class="z-50 max-h-80 min-w-[var(--kb-popper-anchor-width)] overflow-y-auto rounded-2xl border bg-card p-1.5 text-card-foreground shadow-xl">
          <SelectPrimitive.Listbox class="outline-none" />
        </SelectPrimitive.Content>
      </SelectPrimitive.Portal>
    </SelectPrimitive>
  )
}

function Check(): JSX.Element {
  return (
    <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
      <path
        d="m5 12.5 4.5 4.5L19 7.5"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  )
}
