// Line icons in the style of SF Symbols, sized by the surrounding text.

const stroke = {
  fill: "none",
  stroke: "currentColor",
  "stroke-width": 2,
  "stroke-linecap": "round",
  "stroke-linejoin": "round",
} as const

export const CheckCircle = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <circle cx="12" cy="12" r="9" />
    <path d="m8.5 12.5 2.5 2.5 4.5-5.5" />
  </svg>
)

export const AlertCircle = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7.5v5.5M12 16.5v.01" />
  </svg>
)

export const Lock = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <rect x="5" y="10.5" width="14" height="10" rx="2.5" />
    <path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" />
  </svg>
)

export const Phone = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
    <path d="M10.5 18.5h3" />
  </svg>
)

export const ArrowUpRight = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <path d="M7 17 17 7M8 7h9v9" />
  </svg>
)

export const ChevronRight = () => (
  <svg
    viewBox="0 0 24 24"
    aria-hidden="true"
    class="size-4 shrink-0 text-muted-foreground"
    {...stroke}
  >
    <path d="m9 6 6 6-6 6" />
  </svg>
)

export const Folder = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2v7.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z" />
  </svg>
)

export const ArrowUp = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true" {...stroke}>
    <path d="M12 19V5M6 11l6-6 6 6" />
  </svg>
)

export const Spinner = (props: { class?: string }) => (
  <svg
    viewBox="0 0 24 24"
    aria-hidden="true"
    class={`animate-spin ${props.class ?? ""}`}
    {...stroke}
  >
    <path d="M12 3a9 9 0 1 0 9 9" />
  </svg>
)
