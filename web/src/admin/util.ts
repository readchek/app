import { ApiError } from "../api.ts"
import { forget } from "../session.ts"

export function message(error: unknown): string {
  return error instanceof Error ? error.message : "Something went wrong. Try again."
}

/** Waits for an API call, and signs this tab out when the server no longer knows its session. */
export async function call<T>(pending: Promise<T>): Promise<T> {
  try {
    return await pending
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) await forget()
    throw error
  }
}

const relative = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" })
const steps: [Intl.RelativeTimeFormatUnit, number][] = [
  ["year", 31_536_000],
  ["month", 2_592_000],
  ["week", 604_800],
  ["day", 86_400],
  ["hour", 3_600],
  ["minute", 60],
]

/** How long ago a time the server gave was, such as "5 minutes ago". */
export function ago(time: string): string {
  const seconds = (Date.parse(time) - Date.now()) / 1000
  for (const [unit, size] of steps) {
    if (Math.abs(seconds) >= size) return relative.format(Math.round(seconds / size), unit)
  }
  return "just now"
}

/** "1 library", "3 libraries". */
export function count(n: number, one: string, many: string): string {
  return `${n.toLocaleString()} ${n === 1 ? one : many}`
}
