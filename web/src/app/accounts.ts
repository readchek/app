import { createSignal } from "solid-js"
import { type Session, signOut } from "../api.ts"

/** A Chek server the reader is signed in to. `expired` once the server stops taking its token. */
export type Account = Session & { expired?: boolean }

// The reading app keeps people signed in across visits, as servers keep
// sessions for 90 days after their last use. The admin panel and content
// settings keep their own session for one tab only, in session.ts.
const key = "chek.accounts"

function stored(): Account[] {
  try {
    const value = localStorage.getItem(key)
    const parsed: unknown = value ? JSON.parse(value) : []
    return Array.isArray(parsed) ? (parsed as Account[]) : []
  } catch {
    return []
  }
}

const [accounts, setAccounts] = createSignal<Account[]>(stored())

export { accounts }

function save(next: Account[]) {
  try {
    localStorage.setItem(key, JSON.stringify(next))
  } catch {
    // Private browsing can refuse storage; accounts last until reload.
  }
  setAccounts(next)
}

// Another tab signing in or out changes what this one shows too.
window.addEventListener("storage", (event) => {
  if (event.key === key) setAccounts(stored())
})

/** The account for a server, by its address. */
export function account(server: string): Account | undefined {
  return accounts().find((a) => a.server === server)
}

/** Keeps a new session, replacing any account on the same server. */
export function addAccount(session: Session) {
  save([...accounts().filter((a) => a.server !== session.server), session])
}

/** Marks an account whose token the server no longer takes, so it can be signed in again. */
export function expire(server: string) {
  if (!account(server) || account(server)?.expired) return
  save(accounts().map((a) => (a.server === server ? { ...a, expired: true } : a)))
}

export async function removeAccount(server: string) {
  const current = account(server)
  save(accounts().filter((a) => a.server !== server))
  // The account is gone from this browser either way; a failed sign-out
  // only leaves the session to expire on the server.
  if (current && !current.expired) await signOut(current).catch(() => {})
}

/** The server's address without its scheme, for showing to people. */
export function host(server: string): string {
  const url = new URL(server)
  return url.host + url.pathname.replace(/\/$/, "")
}

/** How an account is named in addresses, such as `/read/chek.example.com/12`. */
export function accountKey(account: Account): string {
  return host(account.server)
}

export function accountByKey(key: string): Account | undefined {
  return accounts().find((a) => accountKey(a) === key)
}
