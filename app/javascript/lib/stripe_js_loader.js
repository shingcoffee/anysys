// Shared loader for the Stripe.js SDK (https://js.stripe.com/v3/), used by
// every Stripe-backed Stimulus controller (payments--sca-recovery,
// payments--stripe-card, …).
//
// A page can mount more than one Stripe controller at once (e.g. the member
// dashboard's subscriptions table + payment methods panel). Without a shared,
// memoized loader, each controller's own copy of "inject a <script> if
// window.Stripe is missing" would race: two controllers connecting in the
// same tick would each see window.Stripe undefined and each inject their own
// <script src="https://js.stripe.com/v3/">, duplicating the SDK on the page.
//
// loadStripeJs() fixes that by memoizing the in-flight load in this module:
//   - If window.Stripe is already present, resolve immediately.
//   - If a load is already in flight, every caller awaits the SAME promise
//     (only one <script> tag is ever injected).
//   - If the load fails (e.g. js.stripe.com is blocked by an ad-blocker or a
//     network policy), the memo is cleared so the NEXT call retries from
//     scratch instead of being permanently stuck on a rejected promise.
const STRIPE_JS_URL = "https://js.stripe.com/v3/"

let pending = null

export function loadStripeJs() {
  if (window.Stripe) return Promise.resolve()
  if (pending) return pending

  pending = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = STRIPE_JS_URL
    script.async = true
    script.onload = resolve
    script.onerror = () => reject(new Error("Failed to load Stripe.js"))
    document.head.appendChild(script)
  }).catch((err) => {
    pending = null
    throw err
  })

  return pending
}

// Test-only seam: clears the memoized in-flight/resolved state so each spec
// starts clean. Application code never needs this — window.Stripe presence
// (or a fresh in-flight load) is the only steady state it relies on.
export function _resetForTests() {
  pending = null
}
