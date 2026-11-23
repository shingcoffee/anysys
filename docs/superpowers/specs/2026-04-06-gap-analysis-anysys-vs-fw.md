# Gap Analysis: anysys vs fw (CiviCore Framework)

**Date:** 2026-04-06
**Purpose:** Compare the business logic builder capabilities of `anysys` against the existing `fw` zero-coding platform and identify features/functionalities that `anysys` is missing.

---

## 1. Conditional / Branching Logic

| Capability | fw | anysys |
|---|---|---|
| **WHERE clause builder (visual)** | Full XML-based WHERE builder with nested AND/OR, field picker, table-aware | Only has connection-level condition builder with simpler rule format |
| **Record-count-based branching** | Conditional module routes by query result count (>, >=, ==, <, <=, !=) | No count-based branching — decisions are only on field value comparisons |
| **Multi-condition fallthrough** | Multiple condition-to-action pairs with a fallback action when none match | Decision is binary (true/false); Switch has multi-way but no fallback-to-action chaining |
| **Calculated field conditions** | Conditions can reference server-side calculated fields (`^@calculatedField.table.field^`) | Conditions reference only context variables, not computed/calculated fields |

**What's missing:** A query-aware conditional that can branch based on "how many records match this query" — not just field value checks. Also, a richer WHERE clause builder UI that's SQL-aware.

---

## 2. Parameter / Configuration System

| Capability | fw | anysys |
|---|---|---|
| **Dynamic parameter overrides** | Parameters can change at runtime based on security profile, device type, language, and custom conditions — with a scoring system to resolve conflicts | No parameter override system — step configurations are static |
| **Parameter inheritance** | Actions inherit parameters from parent sections; parameters cascade down | No inheritance model between flowcharts |
| **Variable replacement in config** | Rich template syntax: `^@fwID^`, `^@field.table.field^`, `^@session.custom.*^`, `[IF(...)]`, `[LINKTO(...)]`, `[AGE(...)]`, `[BARCODE(...)]` | Only `{{variable}}` and `ctx.field` interpolation |
| **Profile-scoped behavior** | Same action shows different columns, buttons, fields depending on user's security profile | No per-role behavioral variation within a single flowchart |
| **Device-aware configuration** | Different parameter values for mobile vs desktop vs tablet | No device-awareness |

**What's missing:** A dynamic configuration layer where the same flowchart/step behaves differently based on who's running it, what device they're on, or what conditions are met at runtime — without duplicating the flowchart.

---

## 3. Data Query Capabilities

| Capability | fw | anysys |
|---|---|---|
| **Multi-table JOIN queries** | Full JOIN system (LEFT, INNER, RIGHT) with aliases, additional WHERE on joins | `query_models` step only queries a single entity — no cross-entity joins |
| **Sub-queries** | Supports sub-queries within WHERE clauses | No sub-query support |
| **Query-driven dropdowns** | `QueryLookup` field type populates dropdowns from live SQL queries | Lookups come from static Constants only |
| **Calculated/computed fields in queries** | SQL expressions computed server-side and usable in WHERE, display, and export | Only `calculate` step for aggregations on collections already in memory |
| **GROUP BY with aggregations** | Full SQL GROUP BY with SUM, COUNT, AVG, MIN, MAX at query level | `aggregate_query` step exists but limited to pluck-then-aggregate pattern |
| **Pagination at query level** | Built-in pagination with configurable page sizes | No pagination support in `query_models` |
| **Query debugging** | `debug` flag shows generated SQL for troubleshooting | No query debugging tools |

**What's missing:** Cross-entity JOIN queries, SQL-level computed fields, proper pagination, and query-driven dynamic dropdowns.

---

## 4. Composite Pages / Inter-Module Events

| Capability | fw | anysys |
|---|---|---|
| **Multiple modules on one page** | `Multiple` module hosts N child modules with independent data sources | Pages are standalone forms — no composite page hosting multiple views |
| **Inter-module events** | Module A triggers refresh/update in Module B via JavaScript events | No inter-component communication |
| **Module visibility conditions** | Each child module can have its own WHERE clause for show/hide | No conditional visibility of page sections based on data queries |
| **Mixed module types** | One page can have a list + form + chart + dashboard widget all interacting | Pages are exclusively form-based — no mixing of lists, charts, and forms |

**What's missing:** The ability to compose a page from multiple independent modules (a list, a form, a chart) that communicate with each other — fw's `Multiple` module pattern.

---


## 5. Calculated Fields (Server-Side SQL)

| Capability | fw | anysys |
|---|---|---|
| **SQL-based calculated fields** | Fields defined as SQL expressions (CASE WHEN, SUM, CONCAT, date arithmetic) computed at query time | `calculate` step only works on in-memory collections |
| **Calculated fields in WHERE** | Filter records using calculated field values | Cannot use computed values in queries |
| **Calculated field chaining** | One calculated field can reference another | No chaining — each step is independent |
| **Display-only computed columns** | Calculated fields shown in lists/forms without storage | Must store computed values in context |

**What's missing:** SQL-level computed fields that are evaluated at query time and usable across the system (in conditions, displays, filters) without storing them.


