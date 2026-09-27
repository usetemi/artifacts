// The page runtime: `window.artifact`, injected by the host right after
// `<head>`, before the page's own scripts. One channel per page carries
// state ops, presence, broadcast, submit, and publish. The page keeps
// rendering from its last known state whenever the connection is down; a
// rejoin replaces the cache with a fresh snapshot, so nothing missed
// offline is lost.

import {Socket, Presence} from "phoenix"
import {applyOps, expand, get} from "./state"
import {isTokenReply, tokenRequestMessage} from "./token_message"

const data = window.__ARTIFACT__
const artifactId = data.id
const appOrigin = data.appOrigin
const viewer = Object.freeze({id: data.viewer.id, name: data.viewer.name})

let version = data.version
let currentToken = data.token
let tokenMintedAt = Date.now()

let leaves = {}
let expanded = null
let joined = false
let stateListeners = new Set()
let presenceListeners = new Set()
let topicListeners = new Map()
let frame = null
let pendingMeta = {}

// The runtime asks for a fresh token before a reconnect that would
// otherwise carry one older than this.
const TOKEN_REFRESH_AFTER_MS = 9 * 60 * 1000
const DEFAULT_RECONNECT_STEPS_MS = [10, 50, 100, 150, 200, 250, 500, 1000, 2000]

function requestTokenRefresh() {
  if (window.parent === window) return
  window.parent.postMessage(tokenRequestMessage(artifactId), appOrigin)
}

window.addEventListener("message", (event) => {
  if (!isTokenReply(event, {appOrigin, parentWindow: window.parent})) return
  currentToken = event.data.token
  tokenMintedAt = Date.now()
})

const socket = new Socket(data.socketUrl, {
  params: () => ({t: currentToken}),
  reconnectAfterMs: (tries) => {
    if (Date.now() - tokenMintedAt > TOKEN_REFRESH_AFTER_MS) requestTokenRefresh()
    return DEFAULT_RECONNECT_STEPS_MS[tries - 1] || 5000
  },
})
const channel = socket.channel(`artifact:${artifactId}`)
const presence = new Presence(channel)

let resolveReady
const ready = new Promise((resolve) => (resolveReady = resolve))

socket.onError(() => requestTokenRefresh())
channel.onError(() => (joined = false))
channel.onClose(() => (joined = false))

channel.on("state:ops", ({ops}) => setLeaves(applyOps(leaves, ops)))
channel.on("version", ({version: number}) => {
  version = number
  if (window.parent === window) window.location.reload()
})
channel.on("broadcast", ({topic, data, from}) => {
  for (const fn of topicListeners.get(topic) ?? []) fn(data, from)
})
presence.onSync(() => {
  for (const fn of presenceListeners) fn(listPresence())
})

function join() {
  channel
    .join()
    .receive("ok", (reply) => {
      joined = true
      version = reply.version
      setLeaves(reply.state)
      if (Object.keys(pendingMeta).length > 0) push("presence:update", {meta: pendingMeta})
      resolveReady()
    })
    .receive("error", (reply) => console.error("artifact: join failed", reply))
}

socket.connect()
join()

function setLeaves(next) {
  leaves = next
  expanded = null
  scheduleNotify()
}

function scheduleNotify() {
  if (frame !== null) return
  frame = requestAnimationFrame(() => {
    frame = null
    const state = currentState()
    for (const fn of stateListeners) fn(state)
  })
}

function currentState() {
  if (expanded === null) expanded = expand(leaves)
  return expanded
}

function push(event, payload) {
  return new Promise((resolve, reject) => {
    if (!joined) return reject(error("unavailable", "not connected"))
    channel
      .push(event, payload)
      .receive("ok", (reply) => resolve(reply ?? {}))
      .receive("error", (reply) => reject(error(reply?.error ?? "error", reply?.error ?? "request failed")))
      .receive("timeout", () => reject(error("unavailable", "request timed out")))
  })
}

function error(code, message) {
  return {code, message}
}

function listPresence() {
  return presence.list((id, {metas: [first]}) => ({id, name: first.name, ...first.meta}))
}

const artifact = {
  get id() {
    return artifactId
  },
  get version() {
    return version
  },
  ready,
  viewer,
  state: {
    get(path) {
      const state = currentState()
      return path === undefined ? state : get(state, path)
    },
    set(path, value) {
      const ops = [{op: "set", path, value}]
      setLeaves(applyOps(leaves, ops))
      return push("state:ops", {ops})
    },
    delete(path) {
      const ops = [{op: "delete", path}]
      setLeaves(applyOps(leaves, ops))
      return push("state:ops", {ops})
    },
    subscribe(fn) {
      stateListeners.add(fn)
      if (joined) fn(currentState())
      return () => stateListeners.delete(fn)
    },
  },
  presence: {
    track(meta) {
      pendingMeta = {...pendingMeta, ...meta}
      if (!joined) return Promise.resolve({})
      return push("presence:update", {meta: pendingMeta})
    },
    list: listPresence,
    onChange(fn) {
      presenceListeners.add(fn)
      return () => presenceListeners.delete(fn)
    },
  },
  broadcast(topic, data) {
    channel.push("broadcast", {topic, data})
  },
  on(topic, fn) {
    if (!topicListeners.has(topic)) topicListeners.set(topic, new Set())
    topicListeners.get(topic).add(fn)
    return () => topicListeners.get(topic)?.delete(fn)
  },
  submit(payload) {
    return push("submit", {payload: payload === undefined ? null : payload})
  },
  publish(html) {
    return push("publish", {html, if_version: version})
  },
}

Object.freeze(artifact.state)
Object.freeze(artifact.presence)
window.artifact = Object.freeze(artifact)
