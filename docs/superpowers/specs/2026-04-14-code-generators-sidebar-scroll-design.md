# Code Generators Page: Independent Scroll & Sidebar Highlight

**Date:** 2026-04-14
**Status:** Approved

## Problem

On the admin code generators page (`/admin/code_generators`):
1. The sidebar and main content scroll as a single unit — when the content is long, the sidebar scrolls off-screen.
2. Clicking a sidebar item updates the content via Turbo Frame but does not re-render the sidebar, so the active highlight does not update.

## Solution

### Independent Scroll

Make the page a fixed viewport-height flex container. Both sidebar and main content get their own scroll contexts.

**Files changed:**
- `app/components/admin/code_generators/index_component.html.erb` — outer container: `min-h-screen` → `h-screen overflow-hidden`; main: add `overflow-y-auto`
- `app/components/admin/code_generators/sidebar_component.html.erb` — nav: add `h-full overflow-hidden` (inner `flex-1 overflow-y-auto` already handles the scrollable category list)

### Sidebar Highlight on Selection

The `active?` method and highlight classes (`bg-indigo-50 text-indigo-700 font-medium`) already exist. The issue is that sidebar links use `data-turbo-frame="generator-content"`, which updates only the content frame — the sidebar never re-renders.

Fix: Remove `data-turbo-frame="generator-content"` from sidebar links. This lets Turbo Drive do a full page visit, re-rendering the sidebar with the correct active state.

**File changed:**
- `app/components/admin/code_generators/sidebar_component.html.erb` — remove `data-turbo-frame="generator-content"` from element type and step action links
