import { type Account, accountByKey } from "../accounts.ts"
import { type Library, libraries } from "../client.ts"

/** The libraries this account may read. The server lists every library, so a reader's are picked out by their grants. */
export async function readableLibraries(account: Account): Promise<Library[]> {
  const all = (await libraries(account)).items
  if (account.user.role === "admin") return all
  return all.filter((library) => account.user.libraryIds.includes(library.id))
}

/** The account a screen's address names, or an error to show when it's missing or signed out. */
export function routeAccount(key: string): Account {
  const account = accountByKey(key)
  if (!account) throw new Error("You're not signed in to this server. Add it in Settings.")
  if (account.expired)
    throw new Error("You were signed out of this server. Sign in again in Settings.")
  return account
}
