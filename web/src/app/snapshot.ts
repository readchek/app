// Reading Now's last answers, kept in this browser so the screen shows at
// once on the next visit while it asks its servers again, as the iOS app
// keeps its home snapshot. Each is named by its account's key and a `|`,
// so signing out forgets that server's.

const prefix = "chek.home."

/** The last answer kept as `name`, if any. */
export function remembered<T>(name: string): T | undefined {
  try {
    const value = localStorage.getItem(prefix + name)
    return value ? (JSON.parse(value) as T) : undefined
  } catch {
    return undefined
  }
}

export function remember(name: string, value: unknown) {
  try {
    localStorage.setItem(prefix + name, JSON.stringify(value))
  } catch {
    // Storage can be full or refused; the screen then waits as before.
  }
}

/** Forgets everything kept for the account with key `account`. */
export function forget(account: string) {
  try {
    for (const name of Object.keys(localStorage)) {
      if (name.startsWith(`${prefix}${account}|`)) localStorage.removeItem(name)
    }
  } catch {
    // Nothing was kept.
  }
}
