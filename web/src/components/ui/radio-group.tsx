import { type JSX, splitProps } from "solid-js"
import { RadioGroup as RadioGroupPrimitive } from "@kobalte/core/radio-group"
import { cn } from "../../lib/cn.ts"

type RadioGroupProps = {
  class?: string
  value?: string
  onChange?: (value: string) => void
  disabled?: boolean
  name?: string
  children: JSX.Element
}

export function RadioGroup(props: RadioGroupProps) {
  const [local, rest] = splitProps(props, ["class"])
  return <RadioGroupPrimitive class={cn("grid", local.class)} {...rest} />
}

export const RadioGroupLabel = (props: { class?: string; children: JSX.Element }) => (
  <RadioGroupPrimitive.Label class={cn("text-sm font-semibold", props.class)}>
    {props.children}
  </RadioGroupPrimitive.Label>
)

/** A choice drawn as a row of a list: the radio, then its label and a line under it. */
export function RadioRow(props: { value: string; title: JSX.Element; description: JSX.Element }) {
  return (
    <RadioGroupPrimitive.Item
      value={props.value}
      class="group relative flex items-start gap-3.5 py-4 data-[disabled]:cursor-default [&:not([data-disabled])]:cursor-pointer"
    >
      <RadioGroupPrimitive.ItemInput class="peer" />
      <RadioGroupPrimitive.ItemControl class="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border-2 border-input transition-colors group-data-[checked]:border-link group-data-[checked]:bg-link group-data-[disabled]:opacity-60 peer-focus-visible:ring-3 peer-focus-visible:ring-ring/35">
        <RadioGroupPrimitive.ItemIndicator class="size-2 rounded-full bg-background" />
      </RadioGroupPrimitive.ItemControl>
      <span class="grid min-w-0 flex-1 gap-0.5">
        <RadioGroupPrimitive.ItemLabel class="flex cursor-[inherit] items-center gap-2 font-semibold after:absolute after:inset-0">
          {props.title}
        </RadioGroupPrimitive.ItemLabel>
        <RadioGroupPrimitive.ItemDescription class="text-[15px] leading-snug text-muted-foreground">
          {props.description}
        </RadioGroupPrimitive.ItemDescription>
      </span>
    </RadioGroupPrimitive.Item>
  )
}
