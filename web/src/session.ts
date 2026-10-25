import { createSignal } from "solid-js"
import { type Session, signOut } from "./api.ts"

// Kept for this tab only, so closing it signs the browser out of nothing
// more than the session it made.
const key = "chek.session"

function stored(): Session | undefined {
  try {
    const value = sessionStorage.getItem(key)
    return value ? (JSON.parse(value) as Session) : undefined
  } catch {
    return undefined
  }
}

const [session, setSession] = createSignal<Session | undefined>(stored())

export { session }

export function remember(value: Session) {
  try {
    sessionStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Private browsing can refuse storage; the session lasts until reload.
  }
  setSession(value)
}

export async function forget() {
  const current = session()
  try {
    sessionStorage.removeItem(key)
  } catch {
    // Nothing was stored.
  }
  setSession(undefined)
  // The session is gone from this tab either way; a failed sign-out only
  // leaves it to expire on the server.
  if (current) await signOut(current).catch(() => {})
}
