# Entity Attributes Detail UI Refactor

## Scope

Entity detail page (`/:cid/admin/maintenance/entities/:id`) only — edit form table unchanged for Visibility column.

## Decisions

1. Hide Visibility column on detail via `show_visibility: false` local on `_attributes_table`.
2. Validators cell on detail: max-width ~9rem, overflow clipped; rich hover tooltip (multiline, body-positioned) via extended `tooltip` Stimulus controller; show only when content overflows.
3. View Attribute modal: keep field set; clearer header (attribute name as title); denser grouped sections — Identity / Audience / Validation / Details (configuration + description).

## Out of scope

- Hiding Visibility on edit form
- Changing attribute edit modal
- Schema / validator semantics
