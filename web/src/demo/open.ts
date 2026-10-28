import { signInToDemo } from "../api.ts"
import { accounts, addAccount } from "../app/accounts.ts"
import { start } from "./server.ts"

/** Starts the demo's own server, and signs in to it on a first visit so the library shows at once. */
export async function openDemo() {
  start()
  if (accounts().length > 0) return
  try {
    addAccount(await signInToDemo())
  } catch {
    // The welcome screen offers to open the demo again.
  }
}
