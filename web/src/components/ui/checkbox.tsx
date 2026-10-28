import type { JSX, ValidComponent } from "solid-js"
import { Match, splitProps, Switch } from "solid-js"

import * as CheckboxPrimitive from "@kobalte/core/checkbox"
import type { PolymorphicProps } from "@kobalte/core/polymorphic"

import { cn } from "../../lib/cn.ts"

// solid-ui's checkbox in Chek's shape. Children follow the box, so a
// CheckboxLabel beside it is tied to it and clicks through.

type CheckboxRootProps<T extends ValidComponent = "div"> =
  CheckboxPrimitive.CheckboxRootProps<T> & { class?: string | undefined; children?: JSX.Element }

const Checkbox = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, CheckboxRootProps<T>>,
) => {
  const [local, others] = splitProps(props as CheckboxRootProps, ["class", "children"])
  return (
    <CheckboxPrimitive.Root
      class={cn("group relative flex cursor-pointer items-start gap-3", local.class)}
      {...others}
    >
      <CheckboxPrimitive.Input class="peer" />
      <CheckboxPrimitive.Control class="mt-px flex size-[22px] shrink-0 items-center justify-center rounded-md border-2 border-input bg-background text-primary-foreground transition-colors peer-focus-visible:ring-3 peer-focus-visible:ring-ring/40 data-[checked]:border-primary data-[checked]:bg-primary data-[disabled]:cursor-not-allowed data-[disabled]:opacity-50 data-[indeterminate]:border-primary data-[indeterminate]:bg-primary">
        <CheckboxPrimitive.Indicator>
          <Switch>
            <Match when={!others.indeterminate}>
              <svg viewBox="0 0 16 16" class="size-3.5" aria-hidden="true">
                <path
                  d="m3.5 8.5 3 3 6-7"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.25"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </Match>
            <Match when={others.indeterminate}>
              <svg viewBox="0 0 16 16" class="size-3.5" aria-hidden="true">
                <path
                  d="M4 8h8"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.25"
                  stroke-linecap="round"
                />
              </svg>
            </Match>
          </Switch>
        </CheckboxPrimitive.Indicator>
      </CheckboxPrimitive.Control>
      {local.children}
    </CheckboxPrimitive.Root>
  )
}

type CheckboxLabelProps<T extends ValidComponent = "label"> =
  CheckboxPrimitive.CheckboxLabelProps<T> & { class?: string | undefined }

const CheckboxLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, CheckboxLabelProps<T>>,
) => {
  const [local, others] = splitProps(props as CheckboxLabelProps, ["class"])
  return (
    <CheckboxPrimitive.Label
      class={cn("cursor-[inherit] leading-snug data-[disabled]:opacity-60", local.class)}
      {...others}
    />
  )
}

export { Checkbox, CheckboxLabel }
