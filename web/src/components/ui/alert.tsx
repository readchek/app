import { type JSX, splitProps } from "solid-js"
import { Alert as AlertPrimitive } from "@kobalte/core/alert"
import { type VariantProps, cva } from "class-variance-authority"
import { cn } from "../../lib/cn.ts"

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

type AlertProps = JSX.HTMLAttributes<HTMLDivElement> &
  VariantProps<typeof alertVariants> & { role?: "alert" | "status" | "note" }

/** A line of news beside the content, led by an icon. Kobalte gives it `role="alert"`; pass `role="status"` for news that isn't urgent. */
export function Alert(props: AlertProps) {
  const [local, rest] = splitProps(props, ["class", "variant"])
  return (
    <AlertPrimitive class={cn(alertVariants({ variant: local.variant }), local.class)} {...rest} />
  )
}
