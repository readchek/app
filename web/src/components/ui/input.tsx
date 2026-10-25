import { type JSX, splitProps } from "solid-js"
import { cn } from "../../lib/cn.ts"

export function Input(props: JSX.InputHTMLAttributes<HTMLInputElement>) {
  const [local, rest] = splitProps(props, ["class"])
  return (
    <input
      class={cn(
        "h-12 w-full rounded-xl border border-input bg-background px-3.5 text-base text-foreground transition-[border-color,box-shadow] placeholder:text-muted-foreground/70 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/25 focus-visible:outline-none disabled:opacity-50",
        local.class,
      )}
      {...rest}
    />
  )
}

export function Label(props: JSX.LabelHTMLAttributes<HTMLLabelElement>) {
  const [local, rest] = splitProps(props, ["class"])
  return <label class={cn("grid gap-1.5 text-sm font-semibold", local.class)} {...rest} />
}
