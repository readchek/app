import type { JSX, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core"
import * as SwitchPrimitive from "@kobalte/core/switch"

import { cn } from "../../lib/cn.ts"

// solid-ui's switch in Chek's shape: a little larger, in brand blue.

const Switch = SwitchPrimitive.Root
const SwitchErrorMessage = SwitchPrimitive.ErrorMessage

type SwitchControlProps = SwitchPrimitive.SwitchControlProps & {
  class?: string | undefined
  children?: JSX.Element
}

const SwitchControl = <T extends ValidComponent = "input">(
  props: PolymorphicProps<T, SwitchControlProps>,
) => {
  const [local, others] = splitProps(props as SwitchControlProps, ["class", "children"])
  return (
    <>
      <SwitchPrimitive.Input class="peer" />
      <SwitchPrimitive.Control
        class={cn(
          "inline-flex h-7 w-12 shrink-0 cursor-pointer items-center rounded-full bg-input p-0.5 transition-colors peer-focus-visible:ring-3 peer-focus-visible:ring-ring/40 data-[checked]:bg-primary data-[disabled]:cursor-not-allowed data-[disabled]:opacity-50",
          local.class,
        )}
        {...others}
      >
        {local.children}
      </SwitchPrimitive.Control>
    </>
  )
}

type SwitchThumbProps = SwitchPrimitive.SwitchThumbProps & { class?: string | undefined }

const SwitchThumb = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SwitchThumbProps>,
) => {
  const [local, others] = splitProps(props as SwitchThumbProps, ["class"])
  return (
    <SwitchPrimitive.Thumb
      class={cn(
        "pointer-events-none block size-6 rounded-full bg-background shadow-sm transition-transform data-[checked]:translate-x-5",
        local.class,
      )}
      {...others}
    />
  )
}

type SwitchLabelProps = SwitchPrimitive.SwitchLabelProps & { class?: string | undefined }

const SwitchLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, SwitchLabelProps>,
) => {
  const [local, others] = splitProps(props as SwitchLabelProps, ["class"])
  return (
    <SwitchPrimitive.Label
      class={cn("cursor-[inherit] font-semibold data-[disabled]:opacity-70", local.class)}
      {...others}
    />
  )
}

type SwitchDescriptionProps = SwitchPrimitive.SwitchDescriptionProps & {
  class?: string | undefined
}

const SwitchDescription = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SwitchDescriptionProps>,
) => {
  const [local, others] = splitProps(props as SwitchDescriptionProps, ["class"])
  return (
    <SwitchPrimitive.Description
      class={cn("text-[15px] leading-snug text-muted-foreground", local.class)}
      {...others}
    />
  )
}

export { Switch, SwitchControl, SwitchThumb, SwitchLabel, SwitchDescription, SwitchErrorMessage }
