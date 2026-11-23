# Platform Shared Resources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a platform-owner Shared Resources section (Constants, Entities, Flowcharts, Pages) under `/81721200/admin/maintenance/platform/` that creates `customer_id` NULL records, with Pages gaining shared/live identity.

**Architecture:** Remount the existing maintenance controllers under the platform scope. A request-path concern forces shared identity, remaps named URL helpers, and scopes finders. RouteAuthorization must gate on request path because reused controllers do not live under `admin/maintenance/platform/` in `controller_path`.

**Tech Stack:** Rails 8.1.2, RSpec, ViewComponent, Stimulus (versions `pathPrefix` only), I18n en + zh-CN.

## Global Constraints

- Grok 4.6 only; no extra roles; admin URLs under `/:cid/admin/`
- Platform tools: `platform_owner?` only, customer `81721200`
- User-facing strings: I18n `en` + `zh-CN`; Stimulus English `default:` + server `data-*-value`
- Shared creates skip tenant billing quota; no auto-commit
- Do not edit unrelated dirty files (rollup attributes, etc.)

---

### Task 1: Page shared identity

**Files:**
- Create: `db/migrate/20260828120000_add_shared_identity_to_pages.rb`
- Modify: `app/models/page.rb`, `app/models/concerns/page_entity_binding.rb`, `spec/factories/pages.rb`, `spec/models/page_spec.rb`

- [ ] Migration: `customer_id` null; integer `type` default 0 not null; index on `type`; unique index on `name` where `customer_id IS NULL AND status = 0`
- [ ] Model: disable STI; `enum :type`; `clear_customer_for_shared`; `accessible` / `shared` scopes; uniqueness; shared page must bind a shared entity
- [ ] `Page#entity` / `entity_id=`: shared pages resolve `Entity.shared`; tenant pages resolve local OR shared
- [ ] Factory trait `:shared` with a shared entity
- [ ] Model specs for NULL customer_id, uniqueness, entity binding

### Task 2: Auth + routes + path remapping

**Files:**
- Modify: `config/routes.rb`, `app/controllers/concerns/route_authorization.rb`, `spec/requests/route_authorization_spec.rb`
- Create: `app/controllers/concerns/admin/maintenance/shared_resource_mode.rb`, `app/helpers/admin/maintenance/platform_path_helper.rb`

- [ ] `RouteAuthorization#platform_namespace?` true when `controller_path` starts with `admin/maintenance/platform/` **or** path matches `/admin/maintenance/platform/`
- [ ] Extract tenant resource routes for constants/entities/flowcharts/pages into a `concern :shared_definition_resources` (omit `entities/:id/entries`) and invoke it inside `scope "platform"`
- [ ] Helper remaps `admin_maintenance_*` → `admin_maintenance_platform_*` when `shared_resources_mode?`
- [ ] Spec: `81721200` admin denied on `/platform/constants`; owner allowed; anonymous redirected

### Task 3: Controller shared mode

**Files:** maintenance constants/entities/flowcharts/pages controllers, nested finders, copies, `soft_deletable_controller.rb` override via concern

- [ ] Include `SharedResourceMode` in those controllers
- [ ] Index/find: platform → `.shared`; tenant → `.accessible` (entities + flowcharts + pages, all tenants)
- [ ] Create: platform forces shared + nil customer + skip quota; tenant forces customer-specific even for owner
- [ ] Copies: source via `accessible`; platform copy stays shared; tenant copy is local
- [ ] Trash in shared mode: `only_deleted` with `customer_id` NULL
- [ ] Page nested finders (`for_current_customer`) → `accessible` so Stimulus tenant JSON URLs still load shared rows for the owner

### Task 4: Sidebar, i18n, type pickers, live pages

**Files:** `maintenance_contributor.rb`, chrome locales, constant/entity/flowchart forms, public/member/admin page lookup, `tree_builder.rb`, versions helper

- [ ] Sidebar section `Shared Resources` + four leaves (I18n en + zh-CN)
- [ ] Remove tenant type=shared pickers; platform forms lock shared
- [ ] Tenant row Edit for shared + owner → platform path
- [ ] `Page.accessible.launched` for public uuid and member show; admin Pages list uses accessible; batch writes stay tenant `customer_id`
- [ ] `versions_i18n_data` sets `pathPrefix` `admin/maintenance/platform` in shared mode

### Task 5: Specs

**Files:** new `spec/requests/admin/maintenance/platform/shared_resources_spec.rb`; update contributor, constants/entities/flowcharts/pages specs that created shared from tenant URLs; page model; public page request spec

- [ ] Owner create on each platform resource → `customer_id` nil
- [ ] Tenant POST type=shared still customer-specific
- [ ] Cross-id 404 on platform path
- [ ] Launched shared page GET `/:other_cid/page/:uuid` 200 when public
- [ ] Tenant copy of shared constant/page creates a local row
- [ ] Run targeted RSpec; fix failures
