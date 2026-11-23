// Shared, memoized loader for third-party captcha SDK <script> tags, used by
// every captcha Stimulus controller (captcha-aliyun, captcha-turnstile, …).
//
// A public form can mount a captcha widget while other controllers are also
// connecting; without a shared memo, two mounts in the same tick would each
// see the SDK global missing and each inject their own <script>, duplicating
// the SDK. loadCaptchaSdk() memoizes the in-flight load per URL:
//   - If `readyCheck()` already reports the SDK present, resolve immediately.
//   - If a load for that URL is in flight, every caller awaits the SAME promise
//     (only one <script> tag is ever injected per URL).
//   - If the load fails (blocked by an ad-blocker / network policy), the memo
//     for that URL is cleared so the NEXT call retries from scratch.
const pending = {}

export function loadCaptchaSdk(url, readyCheck) {
  if (readyCheck && readyCheck()) return Promise.resolve()
  if (pending[url]) return pending[url]

  pending[url] = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = url
    script.async = true
    script.onload = resolve
    script.onerror = () => reject(new Error(`Failed to load captcha SDK: ${url}`))
    document.head.appendChild(script)
  }).catch((err) => {
    delete pending[url]
    throw err
  })

  return pending[url]
}

// Test-only seam: clears memoized in-flight/resolved state so each spec starts
// clean. Application code never needs this.
export function _resetForTests() {
  for (const key of Object.keys(pending)) delete pending[key]
}
