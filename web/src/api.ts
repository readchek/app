// The parts of the Chek server API the web app uses. Requests carry the
// session as a bearer token, never a cookie; see the server's docs/server.md,
// "The web app".

export type Rating = "safe" | "suggestive" | "erotica" | "pornographic"

export const ratings: readonly Rating[] = ["safe", "suggestive", "erotica", "pornographic"]

export type Role = "admin" | "reader"

export type User = {
  id: number
  name: string
  role: Role
  libraryIds: number[]
  createdAt: string
  demo?: boolean
}

export type Session = { server: string; token: string; user: User }

/** Whether this build is the demo, which answers the API itself from a snapshot; see demo/server.ts. */
export const demo = import.meta.env.MODE === "demo"

/** Where the demo lives. The demo build is its own server, at its own address. */
export const demoServer = demo ? location.origin : "https://demo.chek.page"
const device = "Chek on the web"

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
    /** The whole error body, for errors that carry more, such as a progress conflict's position. */
    readonly body?: unknown,
  ) {
    super(message)
  }
}

/** The server's address as typed, without a trailing slash, or an error to show. */
export function serverAddress(typed: string): string {
  let url: URL
  try {
    url = new URL(/^[a-z]+:\/\//i.test(typed.trim()) ? typed.trim() : `https://${typed.trim()}`)
  } catch {
    throw new ApiError("Enter your Chek server's address, such as chek.example.com.", 0)
  }
  // A page served over https can't reach a server on plain http.
  if (url.protocol !== "https:" && location.protocol === "https:") {
    throw new ApiError("Your Chek server needs an https address to be reached from the web app.", 0)
  }
  return url.origin + url.pathname.replace(/\/+$/, "")
}

/** Whether this build is the admin panel the Chek server serves itself, at its own address. */
export const bundled = import.meta.env.MODE === "server"

export async function request<T>(
  server: string,
  path: string,
  init: { method?: string; token?: string; body?: unknown; signal?: AbortSignal } = {},
): Promise<T> {
  let response: Response
  try {
    response = await fetch(`${server}${path}`, {
      method: init.method ?? "GET",
      cache: "no-store",
      signal: init.signal,
      headers: {
        ...(init.token ? { Authorization: `Bearer ${init.token}` } : {}),
        ...(init.body ? { "Content-Type": "application/json" } : {}),
      },
      body: init.body ? JSON.stringify(init.body) : undefined,
    })
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error
    throw new ApiError(
      "Couldn't reach your Chek server. Check the address, and that the server is up to date.",
      0,
    )
  }
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as { code?: string; message?: string }
    throw new ApiError(
      body.message ? sentence(body.message) : `The server answered ${response.status}.`,
      response.status,
      body.code,
      body,
    )
  }
  return (response.status === 204 ? undefined : await response.json()) as T
}

// The server's messages are lowercase phrases, written to be embedded.
function sentence(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1) + (/[.!?]$/.test(text) ? "" : ".")
}

/** Signs in with a one-time code from the app's link. */
export async function openLink(server: string, code: string): Promise<Session> {
  const session = await request<{ token: string; user: User }>(server, "/api/v1/auth/web-link", {
    method: "POST",
    body: { code, device },
  })
  return withDemo(server, session.token)
}

export async function signIn(server: string, name: string, password: string): Promise<Session> {
  const session = await request<{ token: string; user: User }>(server, "/api/v1/auth/sign-in", {
    method: "POST",
    body: { name, password, device },
  })
  return withDemo(server, session.token)
}

/** Signs in to the demo build's own server, which takes any name. */
export function signInToDemo(): Promise<Session> {
  return signIn(demoServer, "demo", "demo")
}

// Only `/me` says whether the account is a demo.
async function withDemo(server: string, token: string): Promise<Session> {
  return { server, token, user: await request<User>(server, "/api/v1/me", { token }) }
}

export async function signOut(session: Session): Promise<void> {
  await request(session.server, "/api/v1/auth/sign-out", { method: "POST", token: session.token })
}

export async function contentRatings(session: Session, signal?: AbortSignal): Promise<Rating[]> {
  const body = await request<{ contentRatings: Rating[] }>(
    session.server,
    "/api/v1/me/content-ratings",
    { token: session.token, signal },
  )
  return body.contentRatings
}

export async function setContentRatings(session: Session, chosen: Rating[]): Promise<Rating[]> {
  const body = await request<{ contentRatings: Rating[] }>(
    session.server,
    "/api/v1/me/content-ratings",
    { method: "PUT", token: session.token, body: { contentRatings: chosen } },
  )
  return body.contentRatings
}
