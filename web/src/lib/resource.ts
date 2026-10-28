import { type Resource, createResource as createSolidResource } from "solid-js"

/**
 * Solid's createResource, except reading it never suspends: it's
 * undefined until the first answer, then the latest one, kept while a
 * new one loads. An error still throws when read, as Solid's does.
 *
 * The router opens each screen in a transition under a Suspense boundary,
 * so with Solid's own resources a screen stayed hidden, and the last one
 * stayed up, until every request on it had answered. With these, a screen
 * opens at once and shows its own placeholders while it loads.
 */
export const createResource = ((...args: Parameters<typeof createSolidResource>) => {
  const [resource, actions] = createSolidResource(...args)
  const read = () => {
    const state = resource.state
    if (state === "ready" || state === "refreshing") return resource.latest
    // Reading an errored resource throws its error without suspending.
    if (state === "errored") return resource()
    return undefined
  }
  Object.defineProperties(read, {
    state: { get: () => resource.state },
    error: { get: () => resource.error },
    loading: { get: () => resource.loading },
    latest: { get: read },
  })
  return [read as Resource<unknown>, actions]
}) as typeof createSolidResource
