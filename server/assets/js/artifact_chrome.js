// The chrome's half of the page-token handshake (DESIGN.md "Page origin and
// runtime", plan §7): the page's runtime asks for a fresh token when its
// socket connect is refused or its current token is getting old; the chrome
// asks the LiveView for one and hands it back over `postMessage`. Both sides
// check origin and source so an embedded page (or another frame entirely)
// can't ask an unrelated chrome for a token, and the chrome never hands a
// token to anything but its own iframe's window.
//
// `isTrustedTokenRequest` is exported standalone so it can be unit-tested
// without a real LiveView `this` (see assets/test/artifact_chrome.test.mjs);
// a colocated hook can't be reached by `node --test`.
export function isTrustedTokenRequest(event, iframe, contentOrigin) {
  return (
    !!iframe &&
    event.origin === contentOrigin &&
    event.source === iframe.contentWindow &&
    event.data != null &&
    event.data.type === "artifact:token-request"
  )
}

export const ArtifactChrome = {
  mounted() {
    const iframe = this.el
    const contentOrigin = iframe.dataset.contentOrigin

    this._onMessage = (event) => {
      if (!isTrustedTokenRequest(event, iframe, contentOrigin)) return

      this.pushEvent("page_token", {}, (reply) => {
        iframe.contentWindow.postMessage(
          {type: "artifact:token", token: reply.token},
          contentOrigin
        )
      })
    }
    window.addEventListener("message", this._onMessage)

    // A new Version: the LiveView pushes the fresh src rather than the hook
    // calling contentWindow.location.reload(), which only works same-origin
    // (DESIGN.md "Page origin and runtime").
    this.handleEvent("page:reload", ({src}) => {
      iframe.src = src
    })
  },

  destroyed() {
    window.removeEventListener("message", this._onMessage)
  },
}
