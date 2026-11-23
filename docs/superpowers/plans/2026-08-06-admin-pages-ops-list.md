# Admin Pages Ops List Implementation Plan

**Goal:** Ops-only admin pages list with publishing slide-over; hide Status column.

**Architecture:** Index embeds `page-publishing` turbo-frame. Show loads slide-over reusing DistributionCard against maintenance launch/visibility with `return_to`.

## Tasks

1. Routes + PagesController#show + return_to on launch/visibility
2. PublishingPanel + index wiring + AdminTable row_path_data + drop Status column
3. Specs + verify
