# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/controllers/property_editor", under: "controllers/property_editor"
pin_all_from "app/javascript/controllers/property_editor/templates", under: "controllers/property_editor/templates"
pin_all_from "app/javascript/controllers/property_editor/branch_manager", under: "controllers/property_editor/branch_manager"
pin_all_from "app/javascript/controllers/property_editor/step_manager", under: "controllers/property_editor/step_manager"
pin_all_from "app/javascript/controllers/entity_form", under: "controllers/entity_form"
pin_all_from "app/javascript/controllers/flowchart_canvas", under: "controllers/flowchart_canvas"
pin_all_from "app/javascript/controllers/page_builder", under: "controllers/page_builder"
pin_all_from "app/javascript/controllers/base_model_config", under: "controllers/base_model_config"
pin_all_from "app/javascript/controllers/payments", under: "controllers/payments"

# Mermaid for diagram rendering
pin "mermaid", to: "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs"

# SortableJS for drag-and-drop list reordering (vendored ESM build)
pin "sortablejs", to: "sortable.esm.js"

# jsdiff for line diffs in the versions UI (vendored ESM build)
pin "diff", to: "diff.js"

# Utility modules
pin "utils", to: "utils/index.js"

# Library modules
pin_all_from "app/javascript/lib", under: "lib"

# Constants
pin_all_from "app/javascript/constants", under: "constants"

# Versions modules (resource-agnostic version diff utility)
pin_all_from "app/javascript/versions", under: "versions"

# Flowchart modules
pin_all_from "app/javascript/flowchart", under: "flowchart"
pin_all_from "app/javascript/flowchart/constants", under: "flowchart/constants"
pin_all_from "app/javascript/flowchart/canvas", under: "flowchart/canvas"
pin_all_from "app/javascript/flowchart/connection_manager", under: "flowchart/connection_manager"
# Rich text editing for Action Text is handled by Lexxy (Lexical-based).
# Assets ship in the lexxy gem; activestorage powers attachment direct uploads.
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
