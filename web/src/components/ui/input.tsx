import { type JSX, splitProps } from "solid-js"
import { cn } from "../../lib/cn.ts"

// The plain input the reader's Contents filter still uses. Everything else
// uses solid-ui's TextField; this goes once the reader moves over too.

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
