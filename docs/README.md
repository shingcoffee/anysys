# Documentation

The maintained reference for how this application works is the in-app developer reference, available to the platform owner at `/:customer_id/admin/maintenance/platform/developer_docs` (customer `81721200`). Its source is `doc/reference/` (`en` and `zh-CN`). Kramdown turns those pages into HTML with heading anchors, and the platform page hosts them.

This directory contains historical design notes and plans. Prefer the in-app reference when the two disagree with the code.

## Directory Layout

| Directory | Contents |
|-----------|----------|
| [`architecture/`](architecture/) | High-level architecture, design patterns, and implementation overviews. |
| [`features/`](features/) | Feature-specific documentation grouped by domain. |
| [`guides/`](guides/) | Step-by-step guides and walkthroughs. |
| [`code-generators/`](code-generators/) | Standards and checklists for the code-generator layer. |
| [`project/`](project/) | Project-level status, gap analysis, and cross-cutting notes. |
| [`plans/`](plans/) | Historical implementation plans. |
| [`superpowers/`](superpowers/) | Archive of AI-assisted design specs and plans. |

## Quick Links

- [AGENTS.md](../AGENTS.md) — Cursor / AI coding conventions

- [How the Generic Model Extensibility Pattern Works](architecture/HOW_IT_WORKS.md)
- [Implementation Overview](architecture/IMPLEMENTATION_OVERVIEW.md)
- [Extensible User Architecture](architecture/EXTENSIBLE_USER_ARCHITECTURE.md)
- [Constants](features/constants/)
- [Flowcharts](features/flowcharts/)
- [Entity Associations](features/entities/)
- [Quick Start Example](guides/QUICK_START_EXAMPLE.md)
- [Generator Authoring Checklist](code-generators/AUTHORING_CHECKLIST.md)
- [Desktop GUI OAuth 2.0 + PKCE](guides/OAUTH_PKCE_DESKTOP.md)
