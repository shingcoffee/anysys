A website page is an ordered list of sections. The table below is generated from the running
application: a section `type` that is not in it is rejected, and a prop that is not in it is dropped.
Every prop is optional and every value other than a list is a string; a text prop you leave out
simply does not render.

- **text** — one line. **long text** — may contain line breaks: `rich_text.body` and `statement.body`
  start a new paragraph at each blank line, a `pricing` tier's `features` is one feature per line,
  and `contact_info.address` keeps its line breaks.
- **image** — an `upload:N` token from the Website images section, an image value already used on
  this website, or left out. A left-out image is filled with curated photography (except `logo_cloud`,
  which then shows the name as a wordmark, and `hero_centered` with `media_mode: none`, which stays text-only).
- **link** — the slug of a page on this site or in this reply (`about`, `our-menu`), or an absolute
  `https://` URL. Nothing else is accepted: no `http://`, `mailto:`, `tel:` or `#anchor`. Email and
  phone belong in `contact_info`, which links them itself.
- **choice** — exactly one of the listed values.
- **list[min–max]** — an array of objects with the item props shown; never more than max items.
- **style** — every section also takes `surface` (`default`, `muted` grey band, `contrast` inverted
  light/dark band, `accent` soft brand tint), most take `spacing` (`default`, `tight`, `roomy`), and
  header-led sections take `align` (`default`, `start`, `center`) for their heading. Leave them out
  for the theme default; use them sparingly to give a long page rhythm (one `contrast` band, a
  `muted` proof section), never on every section.

### Purposes
- `hero_cinematic` — Page-opening photo hero. `tone` `dark` sets the headline low over a full-bleed photograph; `light` centres it above a very wide framed still. For one strong landscape photo: storefront, interior, venue, landscape.
- `hero_split` — Page-opening hero with headline, subhead and buttons on one side and a tall framed photo (`visual_url`) on the other. Suits a portrait or square shot of the product, the people or the work.
- `hero_centered` — Page-opening centred headline with a small eyebrow pill and buttons. `media_mode` defaults to `image`, with a wide screenshot-style frame for software, a product screen or a tidy landscape shot. Set `media_mode` to `none` for a compact text-only hero with no image frame or automatic photography.
- `ai_preview` — Static illustrative request-to-draft preview, not a working assistant. A violet request panel pairs `prompt_label`, `prompt` and `review_note` with one to four output cards (`title`, `body`, `status`), under optional `example_label` and `output_label` copy. Label the example honestly and describe reviewable drafts; no images or live generation claims.
- `statement` — Typographic opener or chapter break: one oversized sentence (`headline`) and a short gloss (`body`) beneath a rule. No image.
- `proof_strip` — A row of big figures with short labels (years open, clients served, rating). Real figures from the admin only.
- `logo_cloud` — "Trusted by" row of client, partner or press names; an uploaded logo shows as a monochrome mark, a name without one as a wordmark.
- `bento_grid` — Mosaic of photo tiles with titles and short text. `span` `hero` is a large two-row tile with the text over the photo, `wide` spans two thirds, `unit` one third. Spaces, highlights, signature offers.
- `alternating_features` — Large photo beside a numbered title and paragraph, the photo switching sides row by row. Two to four services or process stages that each deserve a picture.
- `feature_grid` — Numbered grid of short titles with a line or two of text, no images. Benefits, services, reasons to choose.
- `steps` — Numbered process of up to six steps with title and text, no images. How booking, ordering or onboarding works.
- `card_grid` — Grid of photo cards with title and text, each optionally linking somewhere. Products, dishes, rooms, services, portfolio pieces.
- `gallery` — Editorial photo plates in asymmetric rows, each with a short caption. A showcase of the work, the venue or events.
- `team_grid` — People with tall portraits, name, role and a short bio. Staff, practitioners, founders.
- `quote` — One large pull-quote with attribution and role. A real endorsement or the founder's own words.
- `testimonials` — Wall of short customer quotes, each with name, role and a small round avatar (initials when there is no photo).
- `pricing` — Up to four plan tiers side by side: name, price, cadence, blurb, feature list and a button; one tier may be `featured`. Optional section-level `featured_label` replaces the localized badge copy on that tier; omitted or blank keeps the default. Packages and memberships.
- `price_list` — Menu-style two-column list of item, dotted leader and price with an optional description, no images. Food and drink menus, treatments, rate cards.
- `faq` — Questions and answers in an accordion beside the heading.
- `cta_band` — Closing call to action: a rounded accent band with headline, one line of body and a single button.
- `rich_text` — Long-form prose column: optional heading, then paragraphs (the first reads as a lead). No image. Story, about, policies.
- `split_image_text` — One photo beside a heading and paragraph; `image_side` puts the photo left or right. A story beat or behind-the-scenes shot.
- `contact_info` — Contact block: heading and a large email link beside address, phone and hours rows (email and phone become links). Closes a Contact page.
- `showcase_tiles` — Stack of large photo tiles in the Apple / Tesla homepage register, each with a kicker, title, one line and two pill links. `size` `full` spans the page, `half` pairs two side by side; `tone` sets each tile light or dark. Flagship products, services or collections, usually right after the nav.
- `timeline` — Dated milestones on a vertical rail beside the heading: `date` (a four-character year shows as a large numeral), title and text. Company history, a project's phases or a changelog.
- `story_index` — Newspaper front page: the first story is the lead with a large photo, the next two sit beside it with small photos, the rest are headline-only briefs. Each story has a section `kicker`, title, dek (`body`), `byline` and optional link. News, journal or blog index.
- `comparison_table` — Plans or models side by side: up to four `column_N` names and rows of a feature `title` with `value_N` per column. Write `✓` for included and leave blank or `—` for not included; any other text is shown as written. Plan, model or membership comparison.
- `listing_grid` — Photo-first cards with an optional `badge`, title, star `rating`, `meta` details line and `price`, each optionally linking somewhere. `aspect` frames every photo `square`, `portrait` (products) or `landscape` (homes, rooms). Stays, properties, products, coffees.
- `agenda` — Programme or timetable rows: `time`, session title, `speaker`, a line of text and a `track` chip. Conference schedule, event programme, class timetable.
- `locations` — Cards for each store, café, club or office with a photo, name, address, hours, phone (becomes a link) and one link such as directions or booking. Multi-location businesses.
- `announcement` — A slim centred pill above or below the hero: a short `badge` ("New"), one line of `body` and an optional arrow link (`link_label`, `href`). Launches, openings, news.
- `product_spotlight` — Apple-style product reveal: centred kicker, large headline, subhead and two links over a big framed product image, then up to four `specs` (`value` + `label`) on a hairline row. One flagship product, model or service.
- `image_banner` — Full-bleed campaign photograph with white kicker, headline, body and one button over a dark scrim. `height` `tall` or `medium`; `placement` puts the text at the `bottom` or `center`. A mid-page campaign moment or a seasonal story.
- `metrics` — Up to four oversized accent figures (`value`) with a `label` and a sentence of context (`body`) under a header. Scale, impact or results. Real figures from the admin only.
- `feature_tabs` — Tabbed tour: up to five tabs, each with a short `label`, a `title`, a paragraph and a large framed image; visitors switch tabs. Product capabilities or service areas that each deserve a picture.
- `split_checklist` — Heading, pitch and one button on one side; up to eight checked benefits (`title` + optional `body`) on the other. Why choose us, what is included, membership perks.
- `collection_rail` — Horizontally scrolling row of picture cards (title, `meta` line, optional link). `aspect` `square`, `portrait` or `landscape`. Categories, collections, playlists, rooms, products.
- `cta_split` — Closing call to action inside a rounded panel: a photo on one side (`image_side`) and kicker, headline, body and two buttons on the other. Hosting, joining, booking or visiting invitations.
