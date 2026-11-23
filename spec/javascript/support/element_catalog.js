/**
 * Installs the committed ElementCatalog fixture into the JS store.
 * Specs that render element forms or look up catalog fields must call this
 * (or import a helper that does) — the store is empty until setElementCatalog.
 */
import catalog from "../fixtures/element_catalog.sample.json"
import { setElementCatalog } from "flowchart/constants/element_registry"

export const SAMPLE_ELEMENT_CATALOG = catalog

export function installSampleElementCatalog() {
  setElementCatalog(catalog)
}

export function clearElementCatalog() {
  setElementCatalog(null)
}
