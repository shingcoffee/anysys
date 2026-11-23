// One request stream per canvas record. Identical in-flight reads share a
// promise; accepted results go to every current subscriber, regardless of
// whether a pane or a background refresh initiated the winning request.
const streams = new WeakMap()

function streamFor(canvas, key) {
  if (!streams.has(canvas)) streams.set(canvas, new Map())
  const streamsByKey = streams.get(canvas)
  if (!streamsByKey.has(key)) streamsByKey.set(key, { request: null, listeners: new Set() })
  return streamsByKey.get(key)
}

export function subscribePinResults(canvas, key, listener) {
  const stream = streamFor(canvas, key)
  stream.listeners.add(listener)
  return () => stream.listeners.delete(listener)
}

export function requestPins(canvas, key, readConfiguration, load, commit) {
  const stream = streamFor(canvas, key)
  const snapshot = JSON.stringify(readConfiguration())
  if (stream.request?.snapshot === snapshot) return stream.request.promise

  const request = { snapshot }
  stream.request = request
  request.promise = (async () => {
    try {
      const pins = await load()
      if (stream.request !== request || JSON.stringify(readConfiguration()) !== snapshot) return
      commit(pins)
      await Promise.all([...stream.listeners].map(listener => listener(pins)))
      return pins
    } finally {
      if (stream.request === request) stream.request = null
    }
  })()
  return request.promise
}
