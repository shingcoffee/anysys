// Shared coordination for top-bar dropdowns (search, locale, help,
// notifications, user menu). Each controller announces when it opens; peers
// listen and close so only one panel is visible at a time.
//
// Why a custom event (not relying on document click): every menu toggle calls
// event.stopPropagation(), which prevents sibling outside-click handlers from
// seeing the click — so without this, two menus can stay open together.

export const TOPBAR_MENU_OPEN = "anysys:topbar-menu-open"

export function announceTopbarMenuOpen(source) {
  document.dispatchEvent(new CustomEvent(TOPBAR_MENU_OPEN, { detail: { source } }))
}

export function onPeerTopbarMenuOpen(sourceElement, closeFn) {
  const handler = (event) => {
    if (event.detail?.source !== sourceElement) closeFn()
  }
  document.addEventListener(TOPBAR_MENU_OPEN, handler)
  return handler
}
