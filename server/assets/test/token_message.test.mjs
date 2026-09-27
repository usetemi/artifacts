import test from "node:test"
import assert from "node:assert/strict"
import {isTokenReply, tokenRequestMessage} from "../js/token_message.js"

const appOrigin = "https://usetemi.art"
const parentWindow = {name: "parent"}
const otherWindow = {name: "other"}

test("tokenRequestMessage names the artifact", () => {
  assert.deepEqual(tokenRequestMessage("abc123"), {type: "artifact:token-request", id: "abc123"})
})

test("accepts a reply from the app origin and window.parent", () => {
  const event = {origin: appOrigin, source: parentWindow, data: {type: "artifact:token", token: "t1"}}
  assert.equal(isTokenReply(event, {appOrigin, parentWindow}), true)
})

test("rejects a reply from any other origin", () => {
  const event = {
    origin: "https://evil.example",
    source: parentWindow,
    data: {type: "artifact:token", token: "t1"},
  }
  assert.equal(isTokenReply(event, {appOrigin, parentWindow}), false)
})

test("rejects a reply whose source is not window.parent, even from the app origin", () => {
  const event = {origin: appOrigin, source: otherWindow, data: {type: "artifact:token", token: "t1"}}
  assert.equal(isTokenReply(event, {appOrigin, parentWindow}), false)
})

test("rejects an unrelated message type", () => {
  const event = {origin: appOrigin, source: parentWindow, data: {type: "artifact:token-request", id: "x"}}
  assert.equal(isTokenReply(event, {appOrigin, parentWindow}), false)
})

test("rejects a reply with no token or a non-string token", () => {
  const missing = {origin: appOrigin, source: parentWindow, data: {type: "artifact:token"}}
  const wrongType = {
    origin: appOrigin,
    source: parentWindow,
    data: {type: "artifact:token", token: 123},
  }
  assert.equal(isTokenReply(missing, {appOrigin, parentWindow}), false)
  assert.equal(isTokenReply(wrongType, {appOrigin, parentWindow}), false)
})

test("rejects a message with no data at all", () => {
  const event = {origin: appOrigin, source: parentWindow}
  assert.equal(isTokenReply(event, {appOrigin, parentWindow}), false)
})
