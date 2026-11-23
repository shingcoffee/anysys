// Vitest stub for `@hotwired/stimulus-loading`, which the app pins in
// config/importmap.rb to the vendored copy shipped by the stimulus-rails gem
// (app/assets/javascripts/stimulus-loading.js) — not an npm package, so there is
// nothing under node_modules for Vite to resolve. This mirrors that gem file's
// `eagerLoadControllersFrom` (the only export controllers/index.js uses) so the
// real bootstrap wiring can be exercised; tests that only care about the call
// itself can still `vi.mock("@hotwired/stimulus-loading", ...)` to intercept it.
function parseImportmapJson() {
  return JSON.parse(document.querySelector("script[type=importmap]").text).imports
}

function registerControllerFromPath(path, under, application) {
  const name = path
    .replace(new RegExp(`^${under}/`), "")
    .replace("_controller", "")
    .replace(/\//g, "--")
    .replace(/_/g, "-")

  if (canRegisterController(name, application)) {
    import(/* @vite-ignore */ path)
      .then(module => registerController(name, module, application))
      .catch(error => console.error(`Failed to register controller: ${name} (${path})`, error))
  }
}

function registerController(name, module, application) {
  if (canRegisterController(name, application)) {
    application.register(name, module.default)
  }
}

function canRegisterController(name, application) {
  return !application.router.modulesByIdentifier.has(name)
}

export function eagerLoadControllersFrom(under, application) {
  const paths = Object.keys(parseImportmapJson()).filter(path => path.match(new RegExp(`^${under}/.*_controller$`)))
  paths.forEach(path => registerControllerFromPath(path, under, application))
}
