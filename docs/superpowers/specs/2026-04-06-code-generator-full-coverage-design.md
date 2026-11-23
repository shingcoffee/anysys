# Code Generator Full Coverage Design

**Date:** 2026-04-06
**Goal:** Enrich the Anysys's code generator set from 59 step action generators to 110, covering all significant programming primitives needed for a general-purpose zero-coding platform.

**Approach:** Focus on programming primitives only — third-party service integrations are handled by the existing `api_call` generator. All new generators follow the existing `BaseGenerator` interface with no infrastructure changes required.

---

## Architecture Notes

- All 51 new generators implement `BaseGenerator` with `generator_metadata`, `generate`, `validate_config`, `example_output`, and `dependencies`
- 4 new categories added to `SourceAssembler::CATEGORIES`: `human_workflow`, `resilience`, `scheduling_time`, `utility`
- File-based, auto-discovered by `GeneratorRegistry` — no migration or model changes
- Human Workflow generators integrate with existing `signal_wait` and `timer` elements for pause/resume mechanics

---

## Section 1: Data Operations (+15 generators)

Enriches the existing 16 data operation generators. Fills gaps in collection manipulation, type handling, and scalar operations.

### 1.1 `reduce_collection`
- **Category:** `data_operations`
- **Purpose:** Fold/accumulate a collection to a single value using a configurable accumulator
- **Config:** `collection_key` (ctx key holding the array), `accumulator_initial` (initial value), `operation` (sum, product, concat, custom expression), `output_key`
- **Example:** Reduce an array of order line items to a total price
- **Output:** `ctx[:output_key] = reduced_value`

### 1.2 `flatten_collection`
- **Category:** `data_operations`
- **Purpose:** Flatten nested arrays into a single-level array
- **Config:** `collection_key`, `depth` (levels to flatten, default: unlimited), `output_key`
- **Example:** Flatten `[[1,2],[3,[4,5]]]` → `[1,2,3,4,5]`

### 1.3 `zip_collections`
- **Category:** `data_operations`
- **Purpose:** Combine two or more collections element-wise into arrays of tuples or merged hashes
- **Config:** `collection_keys` (array of ctx keys), `mode` (tuples or merge), `output_key`
- **Example:** Zip `[:a,:b]` with `[1,2]` → `[[:a,1],[:b,2]]` or `[{key: :a, val: 1}, ...]`

### 1.4 `chunk_collection`
- **Category:** `data_operations`
- **Purpose:** Split a collection into sub-arrays of size N
- **Config:** `collection_key`, `chunk_size`, `output_key`
- **Example:** Chunk `[1,2,3,4,5]` by 2 → `[[1,2],[3,4],[5]]`

### 1.5 `partition_collection`
- **Category:** `data_operations`
- **Purpose:** Split collection into two groups based on a predicate (keeps both matching and non-matching)
- **Config:** `collection_key`, `condition` (structured condition like decision generator), `matched_key`, `unmatched_key`
- **Example:** Partition orders into `approved` and `rejected` groups

### 1.6 `find_in_collection`
- **Category:** `data_operations`
- **Purpose:** Find the first element matching a condition, return element and index
- **Config:** `collection_key`, `condition`, `output_key`, `index_key` (optional)
- **Example:** Find first overdue invoice in a collection

### 1.7 `any_all_none_check`
- **Category:** `data_operations`
- **Purpose:** Boolean check on a collection: any?, all?, or none? match a condition
- **Config:** `collection_key`, `check_type` (any/all/none), `condition`, `output_key`
- **Output:** `ctx[:output_key] = true/false`
- **Example:** Check if all line items have a price > 0 before submitting an order

### 1.8 `coalesce_value`
- **Category:** `data_operations`
- **Purpose:** Return the first non-nil value from an ordered list of ctx keys or literal values
- **Config:** `candidates` (array of `{type: "ctx_key"|"literal", value: ...}`), `output_key`
- **Example:** Use `ctx[:user_name] || ctx[:email] || "Anonymous"` as display name

### 1.9 `type_cast`
- **Category:** `data_operations`
- **Purpose:** Convert a value between types with configurable error handling
- **Config:** `source_key`, `target_type` (string, integer, float, boolean, date, datetime, array, hash), `format` (optional, for date parsing), `on_failure` (nil, default_value, raise), `output_key`
- **Example:** Cast string `"42"` to integer, or parse `"2026-01-15"` to Date

### 1.10 `string_manipulate`
- **Category:** `data_operations`
- **Purpose:** Perform structural string operations (not interpolation — that's `format_string`)
- **Config:** `source_key`, `operation` (split, join, trim, strip, pad_left, pad_right, truncate, upcase, downcase, capitalize, camelize, underscore, reverse, replace, gsub), `params` (operation-specific: delimiter, length, pad_char, pattern, replacement), `output_key`
- **Example:** Split a CSV line by comma, truncate a description to 100 chars, convert `"user_name"` to `"UserName"`

### 1.11 `math_operation`
- **Category:** `data_operations`
- **Purpose:** Perform scalar math operations beyond aggregation
- **Config:** `operands` (array of ctx keys or literals), `operation` (add, subtract, multiply, divide, modulo, power, sqrt, abs, floor, ceil, round, random, min, max), `precision` (optional decimal places for round), `output_key`
- **Example:** Round a calculated tax amount to 2 decimal places, generate a random 6-digit verification code

### 1.12 `hash_manipulate`
- **Category:** `data_operations`
- **Purpose:** Reshape hash/object structures
- **Config:** `source_key`, `operation` (pick, omit, keys, values, deep_merge, diff, rename_keys, invert), `params` (operation-specific: key list, merge source, rename map), `output_key`
- **Example:** Pick only `[:name, :email]` from a user hash for an API payload, diff two record versions

### 1.13 `base64_encode_decode`
- **Category:** `data_operations`
- **Purpose:** Encode or decode Base64 strings
- **Config:** `source_key`, `operation` (encode, decode, urlsafe_encode, urlsafe_decode), `output_key`
- **Example:** Encode a file's content for embedding in JSON, decode a Base64-encoded API response

### 1.14 `generate_id`
- **Category:** `data_operations`
- **Purpose:** Generate unique identifiers
- **Config:** `format` (uuid_v4, ulid, nanoid, custom_pattern), `pattern` (for custom: `"ORD-{YYYY}{MM}{DD}-{SEQ6}"`), `output_key`
- **Example:** Generate a correlation ID for tracing a multi-step workflow, create a human-readable order number

### 1.15 `compare_data`
- **Category:** `data_operations`
- **Purpose:** Diff two objects/hashes, return added, removed, and changed fields
- **Config:** `left_key`, `right_key`, `ignore_keys` (optional), `output_key`
- **Output:** `ctx[:output_key] = { added: {...}, removed: {...}, changed: {field: {from: x, to: y}} }`
- **Example:** Compare a record before/after update for audit logging

---

## Section 2: Model Operations (+5 generators)

Adds compound CRUD patterns that currently require chaining 3-5 steps.

### 2.1 `upsert_model`
- **Category:** `model_operations`
- **Purpose:** Atomic find-or-create / update-or-insert
- **Config:** `entity_id`, `match_fields` (fields to match existing record on), `attributes` (hash of fields to set), `output_key`, `created_key` (boolean indicating whether record was created or updated)
- **Generated code:** Uses `find_or_initialize_by` + attribute assignment + save, wrapped appropriately
- **Example:** Sync customer records from external system — create if new, update if exists

### 2.2 `clone_model`
- **Category:** `model_operations`
- **Purpose:** Deep duplicate a record, optionally including specified associations
- **Config:** `source_key` (ctx key holding original record), `include_associations` (array of association names to also clone), `override_attributes` (hash of fields to override on the clone), `output_key`
- **Example:** Clone an order template to create a new order, overriding the customer and date

### 2.3 `soft_delete_model`
- **Category:** `model_operations`
- **Purpose:** Mark a record as deleted without removing from database
- **Config:** `source_key`, `deleted_field` (default: `deleted_at`), `deleted_value` (default: `Time.current`), `cascade_to` (optional associations to also soft-delete)
- **Example:** Soft-delete a user account, cascading to their posts and comments

### 2.4 `bulk_import`
- **Category:** `model_operations`
- **Purpose:** Efficiently insert multiple records from structured data with validation
- **Config:** `entity_id`, `data_key` (ctx key holding array of hashes), `field_mapping` (optional mapping from source keys to model fields), `on_duplicate` (skip, update, raise), `batch_size` (default: 1000), `output_key` (import result with counts)
- **Generated code:** Uses `insert_all` or `upsert_all` with batching
- **Example:** Import 10,000 product records from a parsed CSV

### 2.5 `raw_sql_query`
- **Category:** `model_operations`
- **Purpose:** Execute parameterized raw SQL, return result set
- **Config:** `sql_template` (SQL with `$1`, `$2` placeholders), `bindings` (array of ctx keys or literals for each placeholder), `output_key`, `single_result` (boolean — return first row or all)
- **Safety:** Parameterized bindings only — no string interpolation. Validation rejects SQL containing unbound interpolation.
- **Example:** Execute a CTE-based hierarchical query or window function that QueryBuilder can't express

---

## Section 3: Security (+4 generators)

Completes the security primitive pairs and adds data protection.

### 3.1 `verify_token`
- **Category:** `security`
- **Purpose:** Decode and verify a JWT or signed token, extract claims
- **Config:** `token_key` (ctx key holding the token string), `algorithm` (HS256, RS256, etc.), `secret_key` or `public_key` (reference to credentials), `required_claims` (optional array of claim names that must be present), `output_key` (decoded payload)
- **Output:** On success: `ctx[:output_key] = {claims hash}`. On failure: returns falsy for Railway routing.
- **Example:** Verify an incoming API token and extract user_id from claims

### 3.2 `decrypt_data`
- **Category:** `security`
- **Purpose:** Decrypt data encrypted by `encrypt_data`
- **Config:** `source_key`, `algorithm` (AES-256-GCM, etc.), `key_reference` (reference to decryption key in credentials), `output_key`
- **Example:** Decrypt stored SSN for authorized display in an admin workflow

### 3.3 `sanitize_input`
- **Category:** `security`
- **Purpose:** Clean user-submitted content to prevent injection attacks
- **Config:** `source_key`, `mode` (strip_tags, escape_html, strip_sql, whitelist_tags), `allowed_tags` (for whitelist mode), `output_key`
- **Example:** Sanitize user bio HTML before storing, allowing only `<b>`, `<i>`, `<a>` tags

### 3.4 `mask_data`
- **Category:** `security`
- **Purpose:** Mask sensitive data for safe display or logging
- **Config:** `source_key`, `mask_type` (last4, first1_last1, email, phone, full, custom), `mask_char` (default: `*`), `output_key`
- **Examples:** `"4111111111111234"` → `"************1234"`, `"john@example.com"` → `"j***@e***.com"`

---

## Section 4: File Operations (+4 generators)

Adds structured data interchange formats and archive handling.

### 4.1 `parse_csv`
- **Category:** `file_operations`
- **Purpose:** Parse CSV content into an array of hashes
- **Config:** `source_key` (ctx key holding CSV string or file reference), `headers` (true/false/array of column names), `delimiter` (default: `,`), `encoding` (default: UTF-8), `skip_blank_lines` (boolean), `type_coerce` (optional hash of column→type mappings), `output_key`
- **Example:** Parse uploaded employee CSV, coercing `hire_date` to Date and `salary` to Float

### 4.2 `generate_csv`
- **Category:** `file_operations`
- **Purpose:** Generate CSV string from a collection
- **Config:** `collection_key`, `columns` (array of `{header: "Name", field: "name", format: optional}`), `delimiter`, `include_headers` (boolean), `output_key`
- **Example:** Export filtered order records as CSV for download

### 4.3 `compress_files`
- **Category:** `file_operations`
- **Purpose:** Create ZIP or GZIP archive from files or in-memory data
- **Config:** `entries` (array of `{name: "filename.txt", source_key: "ctx_key"}` or `{name: ..., literal: "content"}`), `format` (zip, gzip), `output_key`
- **Example:** Bundle multiple generated reports into a single ZIP for email attachment

### 4.4 `decompress_files`
- **Category:** `file_operations`
- **Purpose:** Extract entries from a ZIP or GZIP archive
- **Config:** `source_key`, `format` (zip, gzip), `filter` (optional glob pattern to extract only matching entries), `output_key` (hash of `{filename => content}`)
- **Example:** Extract all `.csv` files from an uploaded ZIP archive for batch processing

---

## Section 5: Caching (+2 generators) & Concurrency (+1 generator)

### 5.1 `cache_delete`
- **Category:** `caching`
- **Purpose:** Invalidate cache entries by key or pattern
- **Config:** `key` (exact key or pattern with `*` wildcard), `mode` (exact, pattern)
- **Example:** After updating a product, delete `"product_#{id}"` and `"product_list_*"` caches

### 5.2 `cache_fetch`
- **Category:** `caching`
- **Purpose:** Read-through cache — read from cache, on miss compute value and store it
- **Config:** `key`, `ttl`, `fallback_expression` (Ruby expression to compute on miss, or `fallback_step` referencing another ctx key to evaluate), `output_key`
- **Example:** Cache expensive aggregate query result for 5 minutes

### 5.3 `release_lock`
- **Category:** `concurrency`
- **Purpose:** Release a lock previously acquired by `acquire_lock`
- **Config:** `lock_key` (same key used in acquire_lock), `lock_token` (optional — for token-based lock verification)
- **Example:** Release inventory lock after reservation is confirmed or rejected

---

## Section 6: Response (+1 generator)

### 6.1 `redirect_response`
- **Category:** `response`
- **Purpose:** Issue an HTTP redirect response
- **Config:** `url` (target URL, supports ctx interpolation), `status` (301, 302, 307, 308), `query_params` (optional hash of params to append), `flash` (optional flash message)
- **Example:** After successful payment form submission, redirect to order confirmation page

---

## Section 7: Human Workflow (NEW category, 4 generators)

New category: `human_workflow`. Must be added to `SourceAssembler::CATEGORIES`.

These generators integrate with the existing `signal_wait` element type for pause/resume mechanics. When a human workflow step pauses the flow, it persists state and creates the relevant UI artifact (approval request, task, input form). When the human acts, a signal resumes the flow.

### 7.1 `approval_gate`
- **Category:** `human_workflow`
- **Purpose:** Pause workflow execution and request approval from one or more users/roles
- **Config:** `approvers` (array of `{type: "user"|"role", id_key: ctx_key}`), `approval_mode` (any, all, majority), `deadline` (duration or absolute datetime), `on_timeout` (approve, reject, escalate), `context_data` (hash of ctx keys to display to approvers), `notification_method` (email, in_app, both), `output_key` (approval result: approved/rejected, approver, timestamp, comments)
- **Generated code:** Creates approval request record, triggers notification, returns signal_wait key for flow suspension
- **Example:** Expense report over $5,000 requires manager approval within 48 hours

### 7.2 `assign_task`
- **Category:** `human_workflow`
- **Purpose:** Create a trackable task assigned to a user or role
- **Config:** `assignee` (`{type: "user"|"role", id_key: ctx_key}`), `title` (string with ctx interpolation), `description`, `priority` (low, medium, high, urgent), `deadline` (optional), `context_data` (hash of ctx keys to attach), `wait_for_completion` (boolean — if true, pauses flow), `output_key` (task record)
- **Example:** Assign "Review application documents" task to the compliance team

### 7.3 `user_input_request`
- **Category:** `human_workflow`
- **Purpose:** Pause workflow and present a form to collect additional data from a user
- **Config:** `target_user` (ctx key for user to prompt), `fields` (array of `{name, type, label, required, options, default}`), `message` (explanation of what's needed), `deadline` (optional), `output_key` (hash of submitted field values)
- **Example:** During customer onboarding, request additional verification documents if initial check is inconclusive

### 7.4 `escalation`
- **Category:** `human_workflow`
- **Purpose:** Escalate a pending human workflow item if not completed within a timeframe
- **Config:** `watched_key` (ctx key of the pending approval/task/input), `timeout` (duration), `escalation_target` (`{type: "user"|"role", id_key: ctx_key}`), `escalation_action` (reassign, notify_additional, auto_approve, auto_reject), `max_escalations` (default: 1), `output_key`
- **Example:** If expense approval not received within 48h, escalate to department head; if still no response in 24h, auto-approve

---

## Section 8: Resilience (NEW category, 4 generators)

New category: `resilience`. Must be added to `SourceAssembler::CATEGORIES`.

### 8.1 `circuit_breaker`
- **Category:** `resilience`
- **Purpose:** Protect against cascading failures by tracking error rates and short-circuiting
- **Config:** `breaker_name` (unique identifier), `failure_threshold` (number of failures before opening), `reset_timeout` (seconds before trying again), `half_open_max` (requests to allow in half-open state), `fallback_expression` (value to return when circuit is open), `output_key`
- **States:** closed (normal) → open (all calls fail fast) → half-open (test single call)
- **Generated code:** Uses Rails cache to persist circuit state across requests
- **Example:** Wrap external payment gateway calls — after 5 failures in 60s, return fallback error for 30s before retrying

### 8.2 `rate_limiter`
- **Category:** `resilience`
- **Purpose:** Throttle operation execution to a maximum rate
- **Config:** `limiter_name` (unique identifier), `max_requests` (N), `window` (seconds), `algorithm` (token_bucket, sliding_window), `on_throttled` (wait, skip, raise), `wait_timeout` (max seconds to wait if `on_throttled: wait`), `output_key` (boolean: was_throttled)
- **Generated code:** Uses Rails cache for distributed rate counting
- **Example:** Limit outgoing API calls to 100/minute to stay within provider quota

### 8.3 `retry_with_backoff`
- **Category:** `resilience`
- **Purpose:** Retry a failed operation with configurable backoff strategy
- **Config:** `max_attempts`, `backoff_type` (exponential, linear, constant), `base_delay` (seconds), `max_delay` (cap), `jitter` (boolean — add randomness), `retry_on` (array of error types/conditions to retry), `output_key` (includes `attempts_made`, `last_error`)
- **Note:** Differs from BaseGenerator's built-in retry by being a first-class configurable step that users can tune per-operation in the flowchart editor
- **Example:** Retry webhook delivery up to 5 times with exponential backoff (1s, 2s, 4s, 8s, 16s)

### 8.4 `idempotency_check`
- **Category:** `resilience`
- **Purpose:** Ensure an operation executes exactly once for a given idempotency key
- **Config:** `key_expression` (ctx keys/literals to compose the idempotency key), `ttl` (how long to remember executed keys), `on_duplicate` (skip, return_cached, raise), `output_key` (includes `is_duplicate` boolean and `cached_result` if available)
- **Generated code:** Check cache/DB for key existence, mark as executed after successful completion
- **Example:** Prevent duplicate payment processing when a webhook is delivered multiple times

---

## Section 9: Scheduling/Time (NEW category, 3 generators)

New category: `scheduling_time`. Must be added to `SourceAssembler::CATEGORIES`.

### 9.1 `deadline_check`
- **Category:** `scheduling_time`
- **Purpose:** Evaluate whether a deadline has passed and calculate time remaining or overdue duration
- **Config:** `deadline_key` (ctx key holding the deadline datetime), `reference_time` (default: `Time.current`, or ctx key), `output_key` (hash: `{passed: bool, remaining_seconds: N, overdue_seconds: N}`)
- **Example:** Check if invoice payment deadline has passed; route to collections workflow if overdue

### 9.2 `business_hours_check`
- **Category:** `scheduling_time`
- **Purpose:** Determine if a given time falls within configurable business hours
- **Config:** `time_key` (default: current time), `schedule` (hash of `{monday: {start: "09:00", end: "17:00"}, ...}`), `timezone`, `holidays` (array of dates or ctx key holding holiday list), `output_key` (hash: `{within_hours: bool, next_open: datetime, next_close: datetime}`)
- **Example:** Route support tickets to live agents during business hours, to bot outside hours

### 9.3 `timezone_convert`
- **Category:** `scheduling_time`
- **Purpose:** Convert a datetime value between timezones
- **Config:** `source_key`, `from_timezone` (IANA timezone or ctx key), `to_timezone` (IANA timezone or ctx key), `output_key`
- **Example:** Convert UTC event timestamp to the recipient's local timezone for email notification

---

## Section 10: Utility (NEW category, 8 generators)

New category: `utility`. Must be added to `SourceAssembler::CATEGORIES`.

### 10.1 `template_render`
- **Category:** `utility`
- **Purpose:** Render a Liquid or ERB template with dynamic variables
- **Config:** `template` (string template or ctx key holding template), `engine` (liquid, erb), `variables` (hash mapping template variable names to ctx keys), `output_key`
- **Note:** Different from `format_string` which does simple interpolation — this supports conditionals, loops, filters, and partials within the template
- **Example:** Render a dynamic email body with conditional sections based on user tier

### 10.2 `audit_log`
- **Category:** `utility`
- **Purpose:** Write a structured, queryable audit entry
- **Config:** `actor_key` (ctx key for who performed the action), `action` (string: created, updated, deleted, approved, etc.), `target_key` (ctx key for the affected record), `metadata` (hash of additional ctx keys to include), `severity` (info, warning, critical)
- **Output:** Writes to a dedicated audit log store (configurable: DB table, log file, or external service)
- **Note:** Different from `log` which is developer debugging — this is a business-level compliance record
- **Example:** Log "Manager Jane approved expense report #1234 for $5,200" with full context

### 10.3 `ai_inference`
- **Category:** `utility`
- **Purpose:** Call an AI/LLM model with a prompt template and structured response parsing
- **Config:** `provider` (openai, anthropic, or custom endpoint), `model`, `prompt_template` (Liquid template with ctx variables), `system_prompt` (optional), `response_format` (text, json_schema), `json_schema` (if response_format is json_schema), `temperature`, `max_tokens`, `api_key_reference` (credentials reference), `output_key`
- **Note:** This is a programming primitive, not a service integration — it handles prompt templating, response parsing, token management, and structured output extraction that raw `api_call` doesn't address
- **Example:** Classify incoming support ticket by category and urgency, extract structured data from unstructured text

### 10.4 `qr_code_generate`
- **Category:** `utility`
- **Purpose:** Generate a QR code image from string data
- **Config:** `data_key` (ctx key holding the string to encode), `size` (pixels), `format` (png, svg), `error_correction` (low, medium, quartile, high), `output_key` (binary image data or base64)
- **Example:** Generate QR code for event ticket containing entry URL

### 10.5 `barcode_generate`
- **Category:** `utility`
- **Purpose:** Generate barcode images in standard formats
- **Config:** `data_key`, `symbology` (code128, ean13, upc_a, code39, qr, data_matrix), `width`, `height`, `format` (png, svg), `output_key`
- **Example:** Generate Code128 barcode for shipping label

### 10.6 `geolocation_lookup`
- **Category:** `utility`
- **Purpose:** Resolve location data from IP or coordinates, or calculate distance
- **Config:** `mode` (ip_to_location, coordinates_to_location, distance), `source_key`, `target_key` (for distance mode), `output_key`
- **Output:** For lookup: `{country, region, city, timezone, lat, lng}`. For distance: `{km, miles}`
- **Note:** Uses configurable provider (MaxMind DB for IP, geocoding API for coordinates)
- **Example:** Determine user's country from IP for data residency routing

### 10.7 `currency_convert`
- **Category:** `utility`
- **Purpose:** Convert monetary amounts between currencies
- **Config:** `amount_key`, `from_currency` (ISO 4217 code or ctx key), `to_currency`, `rates_source` (static_table, ctx_key, or api), `rates_key` (ctx key holding rates hash if source is ctx_key), `precision` (decimal places, default: 2), `output_key`
- **Example:** Convert EUR invoice amount to USD for consolidated financial reporting

### 10.8 `i18n_translate`
- **Category:** `utility`
- **Purpose:** Look up translated string by key and locale with interpolation and pluralization
- **Config:** `translation_key` (dot-separated key path), `locale` (or ctx key), `interpolations` (hash of variable names to ctx keys), `count` (for pluralization, ctx key or literal), `fallback_locale` (default: en), `output_key`
- **Note:** Uses Rails I18n backend — translations defined in standard `config/locales/*.yml` files
- **Example:** Generate localized notification message: `"You have 3 new orders"` in the user's preferred language

---

## Summary

| Category | Existing | New | Total |
|----------|----------|-----|-------|
| Data Operations | 16 | +15 | 31 |
| Model Operations | 12 | +5 | 17 |
| Security | 5 | +4 | 9 |
| File Operations | 3 | +4 | 7 |
| Caching | 2 | +2 | 4 |
| Concurrency | 1 | +1 | 2 |
| Response | 1 | +1 | 2 |
| Human Workflow (new) | — | +4 | 4 |
| Resilience (new) | — | +4 | 4 |
| Scheduling/Time (new) | — | +3 | 3 |
| Utility (new) | — | +8 | 8 |
| *Unchanged* | 17 | — | 17 |
| **Total** | **59** | **+51** | **110** |

### Infrastructure Changes Required

1. Add 4 new categories to `SourceAssembler::CATEGORIES`:
   ```ruby
   CATEGORIES = %i[
     flow_control model_operations validation data_operations
     communication security background file_operations realtime response
     concurrency service_invocation caching
     human_workflow resilience scheduling_time utility
   ]
   ```

2. Create directory structure under `app/services/code_generators/element_types/process/`:
   ```
   human_workflow/
   resilience/
   scheduling_time/
   utility/
   ```

3. No database migrations required — all generators are file-based.

4. Human Workflow generators will need supporting UI components for approval/task management (separate spec).

### Gem Dependencies (New)

| Generator | Gem | Purpose |
|-----------|-----|---------|
| `qr_code_generate` | `rqrcode` | QR code generation |
| `barcode_generate` | `barby` + `chunky_png` | Barcode generation |
| `geolocation_lookup` | `maxmind-geoip2` | IP geolocation |
| `parse_csv` / `generate_csv` | stdlib `csv` | CSV handling (no gem needed) |
| `template_render` (Liquid) | `liquid` | Liquid template engine |
| `ai_inference` | `ruby-openai` / `anthropic` | AI provider SDKs |
| `compress_files` / `decompress_files` | stdlib `zip` | Archive handling (no gem needed) |
