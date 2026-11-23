/**
 * Installs the committed ActionCatalog fixture into the JS store.
 * Specs that render step forms or look up actions must call this (or import
 * a helper that does) — the store is empty until setActionCatalog runs.
 */
import catalog from "../fixtures/action_catalog.sample.json"
import { setActionCatalog } from "flowchart/constants/action_registry"

export const SAMPLE_ACTION_CATALOG = catalog

export function installSampleActionCatalog() {
  setActionCatalog(catalog)
}

export function clearActionCatalog() {
  setActionCatalog(null)
}
