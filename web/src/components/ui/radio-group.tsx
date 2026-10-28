import type { JSX, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as RadioGroupPrimitive from "@kobalte/core/radio-group"

import { cn } from "../../lib/cn.ts"

// solid-ui's radio group in Chek's shape: each item is a row of a list, the
// radio, then its label and a line under it. The whole row picks it.

type RadioGroupRootProps<T extends ValidComponent = "div"> =
  RadioGroupPrimitive.RadioGroupRootProps<T> & { class?: string | undefined }

const RadioGroup = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, RadioGroupRootProps<T>>,
) => {
  const [local, others] = splitProps(props as RadioGroupRootProps, ["class"])
  return <RadioGroupPrimitive.Root class={cn("grid", local.class)} {...others} />
}

type RadioGroupLabelProps<T extends ValidComponent = "span"> =
  RadioGroupPrimitive.RadioGroupLabelProps<T> & { class?: string | undefined }

/** The group's own name, such as "Role". */
const RadioGroupLabel = <T extends ValidComponent = "span">(
  props: PolymorphicProps<T, RadioGroupLabelProps<T>>,
) => {
  const [local, others] = splitProps(props as RadioGroupLabelProps, ["class"])
  return <RadioGroupPrimitive.Label class={cn("text-sm font-semibold", local.class)} {...others} />
}

type RadioGroupItemProps<T extends ValidComponent = "div"> =
  RadioGroupPrimitive.RadioGroupItemProps<T> & {
    class?: string | undefined
    children?: JSX.Element
  }

const RadioGroupItem = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, RadioGroupItemProps<T>>,
) => {
  const [local, others] = splitProps(props as RadioGroupItemProps, ["class", "children"])
  return (
    <RadioGroupPrimitive.Item
      class={cn(
        "group relative flex items-start gap-3.5 py-4 data-[disabled]:cursor-default [&:not([data-disabled])]:cursor-pointer",
        local.class,
      )}
      {...others}
    >
      <RadioGroupPrimitive.ItemInput class="peer" />
      <RadioGroupPrimitive.ItemControl class="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border-2 border-input transition-colors group-data-[checked]:border-link group-data-[checked]:bg-link group-data-[disabled]:opacity-60 peer-focus-visible:ring-3 peer-focus-visible:ring-ring/35">
        <RadioGroupPrimitive.ItemIndicator class="size-2 rounded-full bg-background" />
      </RadioGroupPrimitive.ItemControl>
      <span class="grid min-w-0 flex-1 gap-0.5">{local.children}</span>
    </RadioGroupPrimitive.Item>
  )
}

type RadioGroupItemLabelProps<T extends ValidComponent = "label"> =
  RadioGroupPrimitive.RadioGroupItemLabelProps<T> & {
    class?: string | undefined
  }

const RadioGroupItemLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, RadioGroupItemLabelProps<T>>,
) => {
  const [local, others] = splitProps(props as RadioGroupItemLabelProps, ["class"])
  return (
    <RadioGroupPrimitive.ItemLabel
      // The label covers the row, so a click anywhere on it picks the item.
      class={cn(
        "flex cursor-[inherit] items-center gap-2 font-semibold after:absolute after:inset-0",
        local.class,
      )}
      {...others}
    />
  )
}

type RadioGroupItemDescriptionProps<T extends ValidComponent = "div"> =
  RadioGroupPrimitive.RadioGroupItemDescriptionProps<T> & {
    class?: string | undefined
  }

const RadioGroupItemDescription = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, RadioGroupItemDescriptionProps<T>>,
) => {
  const [local, others] = splitProps(props as RadioGroupItemDescriptionProps, ["class"])
  return (
    <RadioGroupPrimitive.ItemDescription
      class={cn("text-[15px] leading-snug text-muted-foreground", local.class)}
      {...others}
    />
  )
}

export {
  RadioGroup,
  RadioGroupLabel,
  RadioGroupItem,
  RadioGroupItemLabel,
  RadioGroupItemDescription,
}
