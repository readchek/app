import type { Component, ComponentProps, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import * as AlertPrimitive from "@kobalte/core/alert"
import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

import { cn } from "../../lib/cn.ts"

// solid-ui's alert, drawn as Chek draws news: a line led by an icon rather
// than a box. Kobalte gives it `role="alert"`; pass `role="status"` for news
// that isn't urgent.

const alertVariants = cva(
  "flex items-start gap-2.5 text-[15px] leading-snug [&>svg]:mt-px [&>svg]:size-[18px] [&>svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "text-muted-foreground",
        success: "text-success",
        destructive: "text-destructive",
      },
    },
    defaultVariants: { variant: "default" },
  },
)

type AlertRootProps<T extends ValidComponent = "div"> = AlertPrimitive.AlertRootProps<T> &
  VariantProps<typeof alertVariants> & { class?: string | undefined }

const Alert = <T extends ValidComponent = "div">(props: PolymorphicProps<T, AlertRootProps<T>>) => {
  const [local, others] = splitProps(props as AlertRootProps, ["class", "variant"])
  return (
    <AlertPrimitive.Root
      class={cn(alertVariants({ variant: local.variant }), local.class)}
      {...others}
    />
  )
}

const AlertTitle: Component<ComponentProps<"h5">> = (props) => {
  const [local, others] = splitProps(props, ["class"])
  return <h5 class={cn("font-semibold text-foreground", local.class)} {...others} />
}

const AlertDescription: Component<ComponentProps<"div">> = (props) => {
  const [local, others] = splitProps(props, ["class"])
  return <div class={cn("grid gap-1", local.class)} {...others} />
}

export { Alert, AlertTitle, AlertDescription }
