// Tenant id is the first 8-digit segment of admin/member/public URLs.
export function customerIdFromPath(pathname = window.location.pathname) {
  const match = pathname.match(/^\/(\d{8})\//)
  return match ? match[1] : null
}
