import type { JSX, ValidComponent } from "solid-js"
import { For, createContext, splitProps, useContext } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as ToggleGroupPrimitive from "@kobalte/core/toggle-group"
import type { VariantProps } from "class-variance-authority"

import { cn } from "../../lib/cn.ts"
import { toggleVariants } from "./toggle.tsx"

// solid-ui's toggle group. With the segmented variant it's Chek's segmented
// control: a muted track with the pressed choice lifted out of it.

const ToggleGroupContext = createContext<VariantProps<typeof toggleVariants>>({
  size: "default",
  variant: "default",
})

type ToggleGroupRootProps<T extends ValidComponent = "div"> =
  ToggleGroupPrimitive.ToggleGroupRootProps<T> &
    VariantProps<typeof toggleVariants> & { class?: string | undefined; children?: JSX.Element }

// Exported as ToggleGroupRoot until the reader moves off the ToggleGroup
// wrapper below; then it takes solid-ui's name.
const ToggleGroupRoot = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, ToggleGroupRootProps<T>>,
) => {
  const [local, others] = splitProps(props as ToggleGroupRootProps, [
    "class",
    "children",
    "size",
    "variant",
  ])

  return (
    <ToggleGroupPrimitive.Root
      class={cn(
        "flex items-center justify-center gap-1",
        local.variant === "segmented" && "grid auto-cols-fr grid-flow-col rounded-xl bg-muted p-1",
        local.class,
      )}
      {...others}
    >
      <ToggleGroupContext.Provider
        value={{
          get size() {
            return local.size
          },
          get variant() {
            return local.variant
          },
        }}
      >
        {local.children}
      </ToggleGroupContext.Provider>
    </ToggleGroupPrimitive.Root>
  )
}

type ToggleGroupItemProps<T extends ValidComponent = "button"> =
  ToggleGroupPrimitive.ToggleGroupItemProps<T> &
    VariantProps<typeof toggleVariants> & { class?: string | undefined }

const ToggleGroupItem = <T extends ValidComponent = "button">(
  props: PolymorphicProps<T, ToggleGroupItemProps<T>>,
) => {
  const [local, others] = splitProps(props as ToggleGroupItemProps, ["class", "size", "variant"])
  const context = useContext(ToggleGroupContext)
  return (
    <ToggleGroupPrimitive.Item
      class={cn(
        toggleVariants({
          size: context.size || local.size,
          variant: context.variant || local.variant,
        }),
        local.class,
      )}
      {...others}
    />
  )
}

/**
 * A labeled choice of one of a few options, drawn as segments. The reader's
 * controls still use this; elsewhere, compose ToggleGroupRoot and
 * ToggleGroupItem.
 */
function ToggleGroup<T extends string>(props: {
  class?: string
  label: string
  value: T
  options: readonly { value: T; label: JSX.Element }[]
  onChange: (value: T) => void
}) {
  return (
    <div class={cn("grid gap-2", props.class)}>
      <span class="text-sm font-semibold">{props.label}</span>
      <ToggleGroupRoot
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
      </ToggleGroupRoot>
    </div>
  )
}

export { ToggleGroup, ToggleGroupRoot, ToggleGroupItem }
