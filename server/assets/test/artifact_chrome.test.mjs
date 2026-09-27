import assert from "node:assert/strict"
import {test} from "node:test"
import {isTrustedTokenRequest} from "../js/artifact_chrome.js"

const CONTENT_ORIGIN = "http://127.0.0.1:4002"

function iframeWithWindow(contentWindow) {
  return {contentWindow}
}

test("accepts a token request from the iframe's own window at the content origin", () => {
  const contentWindow = {}
  const iframe = iframeWithWindow(contentWindow)
  const event = {
    origin: CONTENT_ORIGIN,
    source: contentWindow,
    data: {type: "artifact:token-request"},
  }

  assert.equal(isTrustedTokenRequest(event, iframe, CONTENT_ORIGIN), true)
})

test("rejects a message from the wrong origin", () => {
  const contentWindow = {}
  const iframe = iframeWithWindow(contentWindow)
  const event = {
    origin: "http://evil.example",
    source: contentWindow,
    data: {type: "artifact:token-request"},
  }

  assert.equal(isTrustedTokenRequest(event, iframe, CONTENT_ORIGIN), false)
})

test("rejects a message from a window other than the iframe's own", () => {
  const iframe = iframeWithWindow({})
  const event = {
    origin: CONTENT_ORIGIN,
    source: {},
    data: {type: "artifact:token-request"},
  }

  assert.equal(isTrustedTokenRequest(event, iframe, CONTENT_ORIGIN), false)
})

test("rejects an unrelated message type", () => {
  const contentWindow = {}
  const iframe = iframeWithWindow(contentWindow)
  const event = {
    origin: CONTENT_ORIGIN,
    source: contentWindow,
    data: {type: "something:else"},
  }

  assert.equal(isTrustedTokenRequest(event, iframe, CONTENT_ORIGIN), false)
})

test("rejects a message with no data", () => {
  const contentWindow = {}
  const iframe = iframeWithWindow(contentWindow)
  const event = {origin: CONTENT_ORIGIN, source: contentWindow, data: null}

  assert.equal(isTrustedTokenRequest(event, iframe, CONTENT_ORIGIN), false)
})
