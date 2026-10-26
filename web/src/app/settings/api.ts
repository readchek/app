import type { Account } from "../accounts.ts"
import { call } from "../client.ts"

// The signed-in person's own account on a server: where they're signed
// in, their password, and the services they sign in with.

/** A device signed in to the account. */
export type DeviceSession = {
  id: number
  /** The label given at sign-in, such as "Chek on the web". */
  device: string | null
  createdAt: string
  /** Updated at most once an hour. */
  lastUsedAt: string
  expiresAt: string
  /** Whether it's this browser. */
  current: boolean
}

/** A sign-in service linked to the account. */
export type Identity = { provider: string; name: string; createdAt: string }

export function sessions(account: Account, signal?: AbortSignal): Promise<DeviceSession[]> {
  return call(account, "/api/v1/me/sessions", { signal })
}

/** Signs a device out. Signing out the current one signs this browser out. */
export function endSession(account: Account, id: number): Promise<void> {
  return call(account, `/api/v1/me/sessions/${id}`, { method: "DELETE" })
}

/** Changes the password, which signs every other device out. */
export function changePassword(
  account: Account,
  currentPassword: string | undefined,
  newPassword: string,
): Promise<void> {
  return call(account, "/api/v1/me/password", {
    method: "PUT",
    body: currentPassword ? { currentPassword, newPassword } : { newPassword },
  })
}

export function identities(account: Account, signal?: AbortSignal): Promise<Identity[]> {
  return call(account, "/api/v1/me/identities", { signal })
}

/** Unlinks a sign-in service. The server refuses when it's the only way to sign in. */
export function unlinkIdentity(account: Account, provider: string): Promise<void> {
  return call(account, `/api/v1/me/identities/${encodeURIComponent(provider)}`, {
    method: "DELETE",
  })
}
