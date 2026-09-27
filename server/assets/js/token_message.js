// The runtime <-> chrome page-token refresh protocol (DESIGN.md "Page
// origin and runtime", section 7's pinned wire shapes), factored out of
// runtime.js so the origin and source checks can be tested without a
// browser or the "phoenix" package, the same way state.js is tested.
//
// The runtime asks the chrome for a fresh token by posting to
// `window.parent` at the app origin; it accepts a reply only when the
// event's origin is that same app origin and its source is `window.parent`
// itself (not just any frame that happens to share the origin).

export function tokenRequestMessage(artifactId) {
  return {type: "artifact:token-request", id: artifactId}
}

export function isTokenReply(event, {appOrigin, parentWindow}) {
  return (
    event?.origin === appOrigin &&
    event?.source === parentWindow &&
    event?.data?.type === "artifact:token" &&
    typeof event.data.token === "string"
  )
}
