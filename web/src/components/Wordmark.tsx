import { cn } from "../lib/cn.ts"

/** Chek's mark and name, drawn as on chek.page: the open book in the
    current color, with its fold cut out in the page behind it. */
export function Wordmark(props: { class?: string }) {
  return (
    <span
      class={cn(
        "inline-flex items-center gap-1.5 font-display text-[28px] leading-none tracking-[-0.06em]",
        props.class,
      )}
    >
      <svg viewBox="0 0 40 40" class="size-[25px]" aria-hidden="true">
        <path
          d="M7 7h11v25H7a4 4 0 0 1-4-4V11a4 4 0 0 1 4-4Zm15 0h11a4 4 0 0 1 4 4v17a4 4 0 0 1-4 4H22Z"
          fill="currentColor"
        />
        <path
          d="m9 19 4 4 7-8 7 8 4-4"
          fill="none"
          stroke="var(--background)"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
      <span class="-mt-1">chek</span>
    </span>
  )
}
