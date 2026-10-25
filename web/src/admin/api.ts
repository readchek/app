// The parts of the Chek server API the admin panel uses, beside the sign-in
// calls in ../api.ts. Shapes follow the server's openapi.yaml.

import { type Role, type Session, type User, request } from "../api.ts"

export type ServerInfo = { version: string; setupRequired: boolean }

export type ScanState = {
  status: "idle" | "scanning" | "failed"
  error: string | null
  finishedAt: string | null
}

export type Library = {
  id: number
  name: string
  kind: "folder" | "source"
  path: string | null
  source?: {
    type: "komga" | "kavita" | "extension"
    url?: string
    libraryIds?: string[]
    extensionId?: string
    progressUserId?: number
  }
  scan: ScanState
  createdAt: string
}

export type Folder = { name: string; path: string }

export type FolderList = {
  path: string
  parent: string | null
  folders: Folder[]
  truncated: boolean
}

export type Credentials =
  | { type: "bearer"; token: string }
  | { type: "basic"; username: string; password: string }
  | { type: "header"; name: string; value: string }

export type Repository = {
  id: number
  url: string
  name: string | null
  allowListed: boolean
  usable: boolean
  hasCredentials: boolean
  extensionCount: number
  fetchedAt: string | null
  fetchError: string | null
  createdAt: string
}

export type Settings = { allowAnyRepository: boolean }

export type NewLibrary =
  | { name: string; path: string }
  | {
      name: string
      komga: {
        url: string
        apiKey?: string
        username?: string
        password?: string
        writeProgress: boolean
      }
    }
  | { name: string; kavita: { url: string; apiKey: string; writeProgress: boolean } }

const auth = (session: Session) => ({ token: session.token })

export function serverInfo(server: string): Promise<ServerInfo> {
  return request<ServerInfo>(server, "/api/v1/server")
}

export async function setUp(
  server: string,
  setupToken: string,
  name: string,
  password: string,
): Promise<Session> {
  const session = await request<{ token: string; user: User }>(server, "/api/v1/setup", {
    method: "POST",
    body: { setupToken, name, password },
  })
  return { server, token: session.token, user: session.user }
}

export async function libraries(session: Session): Promise<Library[]> {
  const body = await request<{ items: Library[] }>(
    session.server,
    "/api/v1/libraries",
    auth(session),
  )
  return body.items
}

export function library(session: Session, id: number): Promise<Library> {
  return request<Library>(session.server, `/api/v1/libraries/${id}`, auth(session))
}

export function addLibrary(session: Session, library: NewLibrary): Promise<Library> {
  return request<Library>(session.server, "/api/v1/libraries", {
    ...auth(session),
    method: "POST",
    body: library,
  })
}

export function renameLibrary(session: Session, id: number, name: string): Promise<Library> {
  return request<Library>(session.server, `/api/v1/libraries/${id}`, {
    ...auth(session),
    method: "PATCH",
    body: { name },
  })
}

export function deleteLibrary(session: Session, id: number): Promise<void> {
  return request(session.server, `/api/v1/libraries/${id}`, { ...auth(session), method: "DELETE" })
}

export function scanLibrary(session: Session, id: number): Promise<void> {
  return request(session.server, `/api/v1/libraries/${id}/scan`, {
    ...auth(session),
    method: "POST",
  })
}

export function folders(session: Session, path?: string): Promise<FolderList> {
  const query = path ? `?${new URLSearchParams({ path })}` : ""
  return request<FolderList>(session.server, `/api/v1/server/folders${query}`, auth(session))
}

export async function users(session: Session): Promise<User[]> {
  const body = await request<{ items: User[] }>(session.server, "/api/v1/users", auth(session))
  return body.items
}

export function createUser(
  session: Session,
  user: { name: string; password: string; role: Role; libraryIds: number[] },
): Promise<User> {
  return request<User>(session.server, "/api/v1/users", {
    ...auth(session),
    method: "POST",
    body: user,
  })
}

export function updateUser(
  session: Session,
  id: number,
  changes: { password?: string; role?: Role; libraryIds?: number[] },
): Promise<User> {
  return request<User>(session.server, `/api/v1/users/${id}`, {
    ...auth(session),
    method: "PATCH",
    body: changes,
  })
}

export function deleteUser(session: Session, id: number): Promise<void> {
  return request(session.server, `/api/v1/users/${id}`, { ...auth(session), method: "DELETE" })
}

export function changePassword(
  session: Session,
  currentPassword: string,
  newPassword: string,
): Promise<void> {
  return request(session.server, "/api/v1/me/password", {
    ...auth(session),
    method: "PUT",
    body: { currentPassword, newPassword },
  })
}

export async function repositories(session: Session): Promise<Repository[]> {
  const body = await request<{ items: Repository[] }>(
    session.server,
    "/api/v1/extension-repositories",
    auth(session),
  )
  return body.items
}

export function addRepository(
  session: Session,
  url: string,
  credentials?: Credentials,
): Promise<Repository> {
  return request<Repository>(session.server, "/api/v1/extension-repositories", {
    ...auth(session),
    method: "POST",
    body: credentials ? { url, credentials } : { url },
  })
}

export function refreshRepository(session: Session, id: number): Promise<Repository> {
  return request<Repository>(session.server, `/api/v1/extension-repositories/${id}/refresh`, {
    ...auth(session),
    method: "POST",
  })
}

export function deleteRepository(session: Session, id: number): Promise<void> {
  return request(session.server, `/api/v1/extension-repositories/${id}`, {
    ...auth(session),
    method: "DELETE",
  })
}

export function settings(session: Session): Promise<Settings> {
  return request<Settings>(session.server, "/api/v1/settings", auth(session))
}

export function updateSettings(session: Session, changes: Settings): Promise<Settings> {
  return request<Settings>(session.server, "/api/v1/settings", {
    ...auth(session),
    method: "PUT",
    body: changes,
  })
}
