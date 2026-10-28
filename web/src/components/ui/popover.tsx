import type { Component, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as PopoverPrimitive from "@kobalte/core/popover"

import { cn } from "../../lib/cn.ts"

// solid-ui's popover: a panel beside the button that opens it, which Kobalte
// keeps on screen, closes on Escape or a click outside, and labels.

const PopoverTrigger = PopoverPrimitive.Trigger

const Popover: Component<PopoverPrimitive.PopoverRootProps> = (props) => {
  return <PopoverPrimitive.Root gutter={8} {...props} />
}

type PopoverContentProps<T extends ValidComponent = "div"> =
  PopoverPrimitive.PopoverContentProps<T> & { class?: string | undefined }

const PopoverContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, PopoverContentProps<T>>,
) => {
  const [local, others] = splitProps(props as PopoverContentProps, ["class"])
  return (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Content
        class={cn(
          "z-50 max-h-[var(--kb-popper-content-available-height)] w-80 max-w-[calc(100vw-2rem)] origin-[var(--kb-popover-content-transform-origin)] overflow-y-auto rounded-2xl border bg-popover p-5 text-popover-foreground shadow-xl outline-none data-[closed]:animate-out data-[closed]:fade-out-0 data-[closed]:zoom-out-98 data-[expanded]:animate-in data-[expanded]:fade-in-0 data-[expanded]:zoom-in-98",
          local.class,
        )}
        {...others}
      />
    </PopoverPrimitive.Portal>
  )
}

type PopoverTitleProps<T extends ValidComponent = "h2"> = PopoverPrimitive.PopoverTitleProps<T> & {
  class?: string | undefined
}

const PopoverTitle = <T extends ValidComponent = "h2">(
  props: PolymorphicProps<T, PopoverTitleProps<T>>,
) => {
  const [local, others] = splitProps(props as PopoverTitleProps, ["class"])
  return (
    <PopoverPrimitive.Title
      class={cn("text-lg leading-tight tracking-[-0.02em]", local.class)}
      {...others}
    />
  )
}

export { Popover, PopoverTrigger, PopoverContent, PopoverTitle }
