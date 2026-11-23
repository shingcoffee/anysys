# Website content editor — clean-minimal left pane

Page 2 (`About`) is the reference surface: `/81721200/admin/modules/website/pages/2/edit`.

## Problem

The left column reads as a CMS form builder (badges, uppercase COPY/LINKS groups, nested cards, raw image URLs, “Reset to layout”). Customers need a writing surface next to the live preview.

## Approaches

1. **Full canvas / WYSIWYG** — edit in the preview. Rejected: Stimulus-only, JSON sections, locked structure.
2. **Recommended: writing rail** — one section at a time, photo-first media, page settings tucked away.
3. **Keep current chrome, add upload** — does not fix the unprofessional left pane.

## Locked design

- Workspace left pane: quiet writing column. Section names as a text list. Only one section open.
- Page title / slug / visibility live in a compact **Page settings** disclosure, not a second card.
- No type badges, group cards, or kit jargon on tenant content-edit.
- Image fields: large preview + Add/Replace photo (file upload or drag-drop). HTTPS URL stays behind **Use a link**.
- Uploads go through ActiveStorage (`Websites::Activities::UploadMedia`). Public URL: `GET /:cid/site/media/:signed_id` (tenant-checked). Stored path replaces the image URL in section JSON.
- `layout_key` may be backfilled when blank; tenants still cannot change structure.
- Slug `media` is reserved.

## Bugs fixed in the same pass

- About page has a blank `layout_key` so layout caption and reset defaults are empty.
- `#validMedia` / `Href.media?` reject app-hosted images (https-only).
- Image control is URL-only; customers cannot replace photography.
