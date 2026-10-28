import type { Component, ComponentProps } from "solid-js"
import { splitProps } from "solid-js"

import { cn } from "../../lib/cn.ts"

/** solid-ui's label, for controls that aren't Kobalte fields. */
const Label: Component<ComponentProps<"label">> = (props) => {
  const [local, others] = splitProps(props, ["class"])
  return (
    <label
      class={cn(
        "text-sm font-semibold peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
        local.class,
      )}
      {...others}
    />
  )
}

export { Label }
