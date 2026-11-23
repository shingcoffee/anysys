# Code Generator Config-Case Enrichment — Design

**Date:** 2026-04-18
**Scope:** All 116 generators under `app/services/code_generators/element_types/`, plus the 14 flow-control element-type schemas in `app/javascript/flowchart/constants/schemas.js`.
**Depth:** Add the next layer of **realistic programming config cases** on top of the 2026-04-17 enrichment. Three layers (Ruby generator, rspec, JS configSchema + Ruby mirror) stay in lockstep.

---

## 1. Problem Statement

The 2026-04-17 enrichment established cross-cutting rules (nil-safe ctx reads, `errorStrategy`, timeout wrapper, canonical variable names) and populated a first round of enum branches. After that pass, the generators compile, handle errors, and pass 2388 rspec examples — but from the perspective of a Ruby/Rails developer mapping a real workflow onto the flowchart, **many realistic programming cases are still missing**. Examples:

- `api_call` handles method + auth, but has no `followRedirects`, `verifySsl`, `responseParseKey` (dig into response body), no query-param builder, no per-status-code retry policy.
- `query_models` handles `where|scope|sql`, but no `select`, `group_by`, `having`, `includes/preload`, `distinct`, `lock`, `readonly`.
- `send_email` handles to+subject+body, but no `cc`, `bcc`, `reply_to`, HTML + plain-text dual body, attachments from ctx, custom headers.
- `cache_write` handles `write|write_if_absent|delete`, but no `compress`, `raw`, `race_condition_ttl`, no namespace prefix, no per-store options.
- `encrypt_data` handles a single algorithm path, but no `aad` (additional authenticated data), no IV/salt override, no key derivation (PBKDF2/HKDF), no Rails MessageEncryptor integration.
- `generate_token` handles basic token generation, but no audience/issuer claims, no `not_before`, no secret source configuration (env / Rails credentials / ctx).

**Goal of this project:** For every generator, the `generate_body` implementation supports the realistic field set an engineer would expect from that operation's Ruby/Rails analogue, `validate_config` rejects every malformed input, rspec covers every new branch, and the JS configSchema (+ Ruby mirror) exposes every field.

---

## 2. Goals & Non-Goals

### Goals
- Real-world config parity per category: each generator supports the fields its mainstream Ruby/Rails library exposes (ActiveRecord, Net::HTTP, ActionMailer, Rails.cache, OpenSSL, JWT, SecureRandom, Liquid, etc.).
- Three-layer invariant preserved: configSchema ↔ validate_config ↔ generate_body ↔ rspec.
- Ruby mirror regenerated from JS so `spec/support/config_schemas.rb` stays in sync.
- Zero regressions on existing 2388 rspec examples.
- New branches are nil-safe (R1), use errorStrategy wrapping (R2), and route through shared helpers (R4) where applicable.

### Non-Goals
- No new element types; only the existing 116 generators (and 14 element-type schemas in `schemas.js`).
- No new ViewComponents or property-editor UI changes. We add field entries to the existing schema-driven popup.
- No refactoring of `BaseGenerator`, `GeneratorRegistry`, `SourceAssembler`, shared helpers. If a gap motivates a new helper, it's added — but the existing modules stay.
- No data migration for old flowchart JSON. Per AGENTS.md rule: "brand-new application, no back-compat".
- No auto-commit.

---

## 3. Architecture (unchanged from 2026-04-17)

```
┌──────────────────────────────────────────────────────────┐
│ JS layer (source of truth)                                │
│  - action_configs/<category>_actions.js  (106 actions)    │
│  - schemas.js :: ELEMENT_SCHEMAS          (14 element-types)│
└─────────────────┬────────────────────────────────────────┘
                  │ rake config_schemas:mirror
                  ▼
┌──────────────────────────────────────────────────────────┐
│ spec/support/config_schemas.rb (Ruby mirror, generated)   │
└─────────────────┬────────────────────────────────────────┘
                  │ reads via Shared::SchemaReader
                  ▼
┌──────────────────────────────────────────────────────────┐
│ Ruby generator  (generate_body + validate_config)         │
│  → reads ctx via Shared::CtxReader (nil-safe)             │
│  → wraps with Shared::ErrorWrapper when risky             │
│  → uses Shared::HttpRequestBuilder, ConditionBuilder,      │
│    OperandConverter as applicable                         │
└─────────────────┬────────────────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────────────────────┐
│ rspec (per-generator spec)                                │
│  - One example per new config branch                       │
│  - Invalid-config example per new validate_config rule     │
│  - Existing "a code generator" shared example stays        │
└──────────────────────────────────────────────────────────┘
```

No architectural changes. This is additive.

---

## 4. Cross-Cutting Enrichment Principles

**P1 — Idiomatic Rails parity.** For every generator, the new fields reflect the method signature of the Ruby/Rails/gem it wraps. Example: `cache_write` adds `compress`, `raw`, `race_condition_ttl`, `namespace` — these are the genuine options `ActiveSupport::Cache::Store#write` accepts.

**P2 — Config fields map 1:1 to code options.** A new field in the JS schema must be consumed by `generate_body` and accepted/rejected by `validate_config`. No dead schema fields.

**P3 — Enum branches must emit non-stub code.** Every new enum value gets a real code branch, not a TODO comment.

**P4 — Sensitive defaults stay.** SSL on, timeouts bounded, parameterized SQL, safe template rendering. New fields never introduce a footgun default.

**P5 — Backward-compat free.** Rename keys if the canonical Rails name differs (e.g., `ttl` → `expiresIn` only if it's clearer; otherwise keep the existing key).

**P6 — Shared helper reuse.** HTTP → `HttpRequestBuilder`. Conditions → `ConditionBuilder`. `ctx.<path>` references → `OperandConverter`. No ad-hoc inline.

---

## 5. Per-Category Field Additions

Each subsection lists the generators in the category, what's already covered, and the **new fields to add**. These are the target of the enrichment; the implementation plan (separate doc) emits one task per generator.

### 5.1 flow_control (14 generators)

Focus: tighten realistic workflow semantics. Most of the new work is on `loop`, `timer`, `signal_wait`, `saga`, `transaction`, `parallel_for_each`, `error_handler`.

- **start** — add `triggerScope` (customer / system / user), `authRequired` (bool), `rateLimitPerMinute` (number) for HTTP trigger; add `eventFilter` (hash) for event trigger.
- **end** — add `cacheControl` (string), `contentType` (select: json|html|xml|text|octet_stream), `cookieOperations` (key_value_list of set/clear), `location` (for 3xx), `triggerWorkflowOnComplete` (text).
- **process** — add `isolateCtx` (bool: deep-dup ctx before steps), `onStepFailure` (select: halt|continue|retry).
- **decision** — add `firstMatchOnly` (bool vs all-match) + `defaultBranchIndex` (number).
- **switch** — add `caseInsensitive` (bool), `allowFallthrough` (bool: run multiple matching cases).
- **loop** — add `breakCondition` (text: early-exit expression), `accumulatorVariable` (text: gather iteration results), `skipCondition` (text: continue on each iter).
- **fork** — add `maxParallelism` (number), `threadPoolName` (select: io|compute|default).
- **join** — add additional strategies (`wait_any`, `wait_n`), `requiredCount` (visible for `wait_n`), `timeoutSeconds`.
- **parallel_for_each** — add `maxConcurrency` (number), `orderedResults` (bool), `errorAggregation` (select: first_error|all_errors|none), `batchSize`.
- **saga** — add `compensationOrder` (select: reverse|parallel|custom), `onCompensationFailure` (select: log|halt|escalate), `isolationLevel` (select for DB saga).
- **signal_wait** — add `signalFilter` (text expression), `cleanupOnTimeout` (bool), `timeoutBehavior` (select: fail|continue|default_value).
- **timer** — add `maxWaitSeconds` (number bound on `until_condition`), `pollIntervalSeconds` (number), `jitter` (bool).
- **transaction** — add `isolationLevel` (select: read_uncommitted|read_committed|repeatable_read|serializable), `timeoutSeconds`, `lockTimeoutSeconds`, `rollbackOnAnyError` (bool).
- **error_handler** — add `errorClassPatterns` (key_value_list for hierarchy matching), `notifyOnError` (select: none|slack|email|webhook), `captureBacktrace` (bool).
- **subflow** — add `subflowId` (text), `inputMapping` (key_value_list), `outputMapping` (key_value_list), `runMode` (select: inline|async|background).

### 5.2 process/data_operations (31 generators)

Focus: edge cases real Ruby code hits — empty collection, nested paths, nil elements, custom predicates, type coercion.

Per generator:

- **assign_value** — add `valueType` extensions: `ctx_ref` (clone of another ctx var), `env_var` (read ENV), `credential` (Rails credentials dig), `random` (for SecureRandom-typed defaults).
- **coalesce_value** — add `operandList` (array of expressions tried in order), `returnFirstNonBlank` vs `returnFirstNonNil`, `blankDefinition` (nil|empty|whitespace).
- **any_all_none_check** — add `predicateType` (select: truthy|match_field|custom_expression|any_of_values), `valueList` (for any_of_values), `resultVar` already present.
- **compare_data** — add `comparisonType` (equality|deep_equal|schema_match|diff), `ignoreKeys` (key_value_list), `caseInsensitive` (bool), `numericTolerance` (number).
- **map_collection** — add `parallel` (bool: use `each_with_object` vs `map.with_object`), `compactResult` (bool), `preserveNilElements` (bool), `indexAwareMapping` (bool: supply idx to expression).
- **filter_collection** — add `rejectMode` (bool: filter out matching), `nilHandling` (select: include|exclude|treat_as_false), chained `secondaryFilter` (text expression for AND).
- **sort_collection** — add `sortFields` (key_value_list of field+direction for multi-key sort), `nullsFirst` (bool), `stable` (bool), `locale` (text: for string sort).
- **group_collection** — add `groupByExpression` (text or nested path), `includeCount` (bool: emit `{group => {items:[], count:n}}`), `sortGroups` (select: key_asc|key_desc|count_asc|count_desc).
- **partition_collection** — add `partitionField`, `limit` (cap each side), `includeStats` (bool).
- **chunk_collection** — add `chunkMode` (select: size|predicate|field), `chunkPredicate` (text), `includeRemainder` (bool), `strict` (drop incomplete final chunk).
- **find_in_collection** — add `returnMode` (select: first|all|last|index), `searchStrategy` (linear|indexed_by), `defaultValue` (text expression).
- **flatten_collection** — add `depth` (number, default 1), `removeNilElements` (bool), `preserveStructure` (bool).
- **uniq_collection** — add `uniqBy` (text: field path or expression), `keepStrategy` (select: first|last).
- **zip_collections** — add `fillValue` (text: pad short arrays), `zipStrategy` (select: strict|longest|shortest), `resultShape` (select: tuples|hashes).
- **reduce_collection** — add `initialValue` (text expression), `accumulatorType` (select: same_as_first|zero|empty_array|empty_hash|custom).
- **pluck_fields** — add `fields` (key_value_list of field paths), `flatten` (bool), `includeSourceIndex` (bool), `renameMapping`.
- **format_string** — add `formatStyle` (select: ruby_interpolation|printf|mustache|liquid), `fallbackOnMissing` (text), `escapeHtml` (bool).
- **parse_data** — add `format` (json|csv|xml|yaml|toml|properties), `csvHeaders` (bool), `csvDelimiter`, `xmlRoot`, `strictMode` (bool: raise on unknown keys), `symbolizeKeys`.
- **serialize_data** — add `format` (json|xml|yaml|csv|msgpack), `pretty` (bool), `includeRoot` (bool), `excludeNils` (bool), `jsonMaxDepth`.
- **regex_extract** — add `regexFlags` (i|m|x|n combo), `captureGroups` (all|named|indexed), `returnType` (select: first|all|named_hash), `fallbackValue`.
- **string_manipulate** — add `operations` (key_value_list: sequence of ops like strip/upcase/gsub) for compound transforms, `regexEscape` (bool), `encoding` (utf8|ascii|latin1).
- **base64_encode_decode** — add `urlSafe` (bool), `stripPadding` (bool), `inputEncoding` (utf8|binary), `lineWidth` (for MIME).
- **calculate** — add `emptyCollectionDefault` (number), `ignoreNils` (bool), `precision` (number), `roundingMode` (select: half_up|half_even|floor|ceiling).
- **date_time_calc** — add `inputFormat` (strftime or iso), `outputFormat`, `businessDays` (bool), `timezone`, `calendarProvider` (select).
- **math_operation** — add `operation` extensions: `modulo`, `power`, `abs`, `floor`, `ceil`, `round`, and `divideByZero` (select: raise|nil|infinity|zero).
- **generate_id** — add `idType` (uuid|uuid_v7|ulid|snowflake|nanoid|hash), `length` (for nanoid), `prefix`, `separator`, `uppercase` (bool).
- **hash_manipulate** — add `operation` extensions: `pick`, `omit`, `deep_merge`, `deep_dup`, `symbolize_keys`, `stringify_keys`, `transform_keys` (with callable), `transform_values`, `compact`, `invert`.
- **log** — add `logger` (select: rails|stdout|file|syslog|audit), `tags` (key_value_list for tagged logging), `includeBacktrace` (bool), `structured` (bool: JSON vs plain), `maxMessageLength`.
- **map_value** — add `fallbackStrategy` (select: default|pass_through|raise), `multiMatch` (return all matches), `caseSensitive` (bool).
- **merge_data** — add `mergeStrategy` (select: shallow|deep|replace|append), `arrayMergeMode` (concat|replace|unique_union), `onConflict` (first|last|error).
- **transform** — add `transformType` extensions: `rename_fields`, `remove_fields`, `add_computed_fields` (key+expression list), `flatten_nested` with separator.
- **type_cast** — add `targetType` extensions: `big_decimal`, `rational`, `complex`, `symbol`, `time`, `date_time`; add `onCastFailure` (select: nil|raise|default).

### 5.3 process/model_operations (17 generators)

Focus: `ActiveRecord::Relation` method parity.

- **find_model** — add `findStrategy` extensions: `find_by_bang` (raises), `first`, `last`, `take`; add `includes` (text for eager load), `lock` (bool, "FOR UPDATE"), `readonly` (bool).
- **new_model** — add `attributes` (key_value_list of field→expression), `skipValidation` (bool), `customerScoped` (bool default true), `associations` (key_value_list for nested attributes).
- **save_model** — add `validate` (bool), `touch` (bool), `context` (string for context-aware validations), `returnUpdated` (bool).
- **update_model** — add `updateStrategy` (select: save|update|update_columns|update_all), `runCallbacks` (bool), `returnChanges` (bool), `lockVersion` (bool: optimistic locking).
- **destroy_model** — add `cascade` (bool), `dependent` (select: destroy|delete|nullify), `confirmWithPassword` (text expression).
- **upsert_model** — add `uniqueBy` (key_value_list of columns), `onConflict` (select: update|skip|raise), `returning` (key_value_list of fields to return), `timestamps` (bool).
- **clone_model** — add `excludeFields` (key_value_list), `overrideFields` (key_value_list), `cloneAssociations` (bool), `depth` (number for deep clone).
- **query_models** — add `select` (text), `distinct` (bool), `groupBy` (text), `having` (text), `includes` (text), `preload` (text), `lock` (bool), `readonly` (bool), `joinConditions` (on separate `joins` hash).
- **count_records** — add `distinct` (bool), `groupBy` (text), `conditions` routed via ConditionBuilder.
- **check_existence** — add `negated` (bool: `none?` variant), `withTransaction` (bool: lock to prevent race).
- **aggregate_query** — add `aggregations` (key_value_list of `sum|avg|min|max|count` + field), `groupBy` (text), `having` (text), `resultFormat` (scalar|hash).
- **pluck_fields** — add `distinct` (bool), `limit` (number), `orderBy`.
- **batch_operation** — add `batchSize` (number, default 1000), `operationType` (select: find_each|in_batches|each_batch|update_all|destroy_all), `progressVar`, `errorCollection` (bool).
- **bulk_import** — add `batchSize`, `validate` (bool), `skipDuplicates` (bool), `onDuplicateKey` (select: update|skip|raise), `returning`, `timestamps`.
- **transition_state** — add `event` (text), `fromState`, `toState`, `guardCondition` (text), `persistImmediately` (bool), `auditTrail` (bool).
- **soft_delete_model** — add `deletedAtField` (text, default `deleted_at`), `deletedByField` (text), `soft_delete_strategy` (paranoia|discard|custom).
- **raw_sql_query** — add `bindings` (key_value_list of parameterized bindings), `resultShape` (select: hash|array|first_value|single_row), `sanitizeInput` (bool, default true).

### 5.4 process/security (9 generators)

Focus: OpenSSL / JWT / bcrypt / Rails MessageEncryptor parity.

- **authenticate** — add `authMethod` (select: password|token|oauth|jwt|api_key|session), `credentialSource` (ctx|params|header), `tokenAlgorithm`, `maxAttempts`, `lockoutSeconds`.
- **authorize** — add `authType` extensions: `ability_check` (CanCanCan), `multi_role` (any_of/all_of roles), `attribute_based` (for ABAC); add `onFailure` (select: raise|return_false|redirect).
- **encrypt_data** — add `algorithm` enum (aes-256-gcm, aes-128-cbc, chacha20-poly1305), `keySource` (credentials|env|ctx|derived), `aad` (text: additional authenticated data), `encoding` (hex|base64|base64url|raw), `deriveKeyFrom` (key+salt pair).
- **decrypt_data** — mirror encrypt; add `verifyAuth` (bool), `onFailure` (select: raise|nil|original).
- **generate_token** — add `tokenType` (jwt|uuid|hex|base58|urlsafe_base64|numeric_otp), `issuer`, `audience`, `notBefore`, `expiresIn`, `claims` (key_value_list), `keyId`, `secretSource` (credentials|env|ctx).
- **verify_token** — add `algorithmAllowlist` (key_value_list), `verifyIssuer`, `verifyAudience`, `leewaySeconds`, `requiredClaims`, `onFailure`.
- **hash_data** — add `algorithm` (bcrypt|scrypt|argon2|pbkdf2|sha256|sha512), `cost`, `salt`, `iterations`, `pepper`, `encoding`.
- **mask_data** — add `maskType` (email|phone|ssn|credit_card|custom), `visibleStart`, `visibleEnd`, `maskChar`, `preserveFormat` (bool), `regexPattern`.
- **sanitize_input** — add `sanitizer` (rails|loofah|custom), `allowedTags` (key_value_list), `allowedAttributes`, `stripTags` (bool), `removeNullBytes`, `maxLength`.

### 5.5 process/communication (4 generators)

- **api_call** — add `followRedirects` (bool), `maxRedirects` (number), `verifySsl` (bool), `queryParams` (key_value_list built into URL), `responseParseKey` (text: dig path), `retryOnStatus` (key_value_list of status codes), `acceptEncoding`, `userAgent`, `connectTimeout` / `readTimeout`, `cookies` (key_value_list), `bodyFormat` (json|form|multipart|text|xml|binary).
- **send_email** — add `cc` (text), `bcc` (text), `replyTo` (text), `from` (text), `htmlBody` (textarea), `textBody` (textarea), `attachments` (key_value_list: ctx ref + filename), `headers` (key_value_list), `priority` (select: low|normal|high), `trackOpens` (bool).
- **send_webhook** — add `hmacAlgorithm` (sha256|sha512|sha1), `signatureHeader` (text, default `X-Signature`), `idempotencyKey` (text), `retryPolicy` (select: none|exponential|linear), `deadLetterVar` (text), `contentType`.
- **notify** — add per-channel fields: Slack (`slackWebhookUrl`, `slackChannel`, `slackMentionUsers`), SMS (`twilioSid`, `twilioToken`, `fromNumber`), Push (`fcmServerKey`, `topic`, `badge`, `sound`), In-App (`priority`, `category`, `targetUrl`). Common: `fallbackChannels` (ordered list).

### 5.6 process/caching (4 generators)

- **cache_read** — add `storeName` (select: :memory|:redis|:memcache|:file|:null), `namespace`, `decompressOnRead`, `versionCheck` (bool), `onMiss` (select: nil|raise|default).
- **cache_write** — add `compress` (bool), `raw` (bool), `race_condition_ttl` (number), `namespace`, `version`, `unlessExist` already supported via action; add `storeName`, `tags` (key_value_list for tag-based invalidation).
- **cache_fetch** — add `raceConditionTtl`, `forceRefresh` (bool), `skipNilCache` (bool), `versionKey`, `fallbackErrorStrategy`.
- **cache_delete** — add `scope` (select: key|pattern|namespace|all|tagged), `tags` (key_value_list), `confirmPattern` (bool: guard destructive ops).

### 5.7 process/concurrency (2 generators)

- **acquire_lock** — add `lockType` (advisory|pessimistic|redis|semaphore), `acquireTimeoutSeconds`, `lockKey`, `holderIdentity`, `retryStrategy` (none|linear|exponential), `heartbeatSeconds`, `onConflict` (select: wait|raise|skip).
- **release_lock** — mirror `acquire_lock` — `lockType`, `lockKey`, `holderIdentity`, `onMissing` (select: ignore|raise|log), `releaseAll` (bool).

### 5.8 process/file_operations (7 generators)

- **download_file** — add `destination` (ctx_var|temp_file|active_storage|s3), `maxSizeBytes`, `followRedirects`, `verifySsl`, `validateChecksum` (text expression), `chunked` (bool for streaming).
- **upload_file** — add `service` (select: active_storage|s3|local|gcs), `maxSizeBytes`, `allowedTypes` (key_value_list MIME), `public` (bool), `metadata` (key_value_list).
- **parse_csv** — add `encoding`, `delimiter`, `quoteChar`, `headerRow` (bool), `skipRows` (number), `colTypes` (key_value_list for type coercion).
- **generate_csv** — add `encoding`, `delimiter`, `headerRow` (bool), `quoteStrings`, `includeBom`, `rowProcessor` (text expression).
- **compress_files** — add `format` (zip|tar|gz|tar_gz), `compressionLevel` (0-9), `passwordProtect` (text), `includeHidden` (bool), `preservePermissions`.
- **decompress_files** — add `format` (auto|zip|tar|gz|tar_gz), `password`, `targetDir`, `pathTraversalGuard` (bool, default true), `overwrite` (bool).
- **generate_file** — add `format` (csv|xlsx|pdf|docx|json|xml|txt), template fields per format (PDF templateName, Excel sheetName, etc.), `outputDestination`.

### 5.9 process/human_workflow (4 generators)

- **approval_gate** — add `mode` (single|majority|unanimous|any_of_n), `requiredCount`, `approverGroup` (text), `timeoutBehavior` (auto_approve|auto_reject|escalate), `delegationAllowed`, `commentsRequired`.
- **assign_task** — add `priority` (low|normal|high|critical), `dueAtExpression`, `taskType`, `notificationChannels` (key_value_list), `checklistItems`, `attachments`.
- **escalation_generator** — add `escalationPolicy` (linear|exponential|fixed), `escalationLevels` (key_value_list of level→recipient), `maxEscalations`, `notificationChannels`, `resetOnAck`.
- **user_input_request** — add `formFields` (key_value_list of name+type+required), `validationRules`, `maxResponseTime`, `notificationChannel`, `resumeBehavior` (block|parallel).

### 5.10 process/realtime (2 generators)

- **broadcast** — add `broadcastType` already there; per type, add Turbo: `turboFrame`, `morphStrategy` (outerHTML|innerHTML|beforebegin|afterend), Action Cable: `channelClass`, `signedStreamName` (bool), `filterCallback`.
- **publish_event** — add `eventBus` (select: rails|kafka|rabbitmq|sns|sidekiq_pub), `partitionKey`, `idempotencyKey`, `priority`, `retryPolicy`, `schemaVersion`.

### 5.11 process/resilience (4 generators)

- **circuit_breaker** — add `failureThreshold`, `successThreshold`, `halfOpenTrialRequests`, `resetTimeoutSeconds`, `windowSizeSeconds`, `jitter` (bool).
- **idempotency_check** — add `keyStrategy` (select: ctx_field|hash_of_inputs|explicit), `ttlSeconds`, `storeName` (redis|db|cache), `onDuplicate` (skip|return_stored|raise).
- **rate_limiter** — add `algorithm` (token_bucket|leaky_bucket|fixed_window|sliding_window), `capacity`, `refillRate`, `burstAllowance`, `onExceed` (wait|raise|return_false|drop).
- **retry_with_backoff** — add `backoffStrategy` (fixed|linear|exponential|decorrelated_jitter), `initialDelay`, `maxDelay`, `maxRetries`, `retryableErrors` (key_value_list), `onExhausted` (raise|return_false|default_value).

### 5.12 process/response (2 generators)

- **render_response** — add `responseFormat` already supports json/html/redirect — add `xml`, `text`, `csv`, `file`, `stream`; add per-format `headers` (key_value_list), `contentType`, `charset`, `etag`, `lastModified`.
- **redirect_response** — add `statusCode` (301|302|303|307|308), `preserveQueryParams` (bool), `addReferrer`, `jsonApiFormat` (bool: return `{redirect_url: ...}` for JSON requests).

### 5.13 process/scheduling_time (3 generators)

- **business_hours_check** — add `schedule` (key_value_list of day→hours), `holidays` (key_value_list of date→name), `timezone`, `resultMode` (bool|next_open|minutes_until_open).
- **deadline_check** — add `deadlineExpression`, `referenceTime` (default Time.current), `gracePeriodSeconds`, `behaviorOnBreach` (mark|raise|signal), `breachedVar`.
- **timezone_convert** — add `sourceTimezone`, `targetTimezone`, `preserveLocalTime` (bool: keep wall-clock vs shift), `outputFormat`, `dstBehavior` (raise_on_ambiguous|prefer_earlier|prefer_later).

### 5.14 process/service_invocation (1 generator)

- **invoke_service** — add `serviceClass` (text), `invocationStyle` (select: call|new_and_call|class_method|instance_method), `methodName`, `args` (key_value_list), `kwargs` (key_value_list), `resultVar`, `definedGuard` (bool: emit `defined?` check), `onMissing` (raise|nil|skip).

### 5.15 process/utility (8 generators)

- **ai_inference** — add `provider` (openai|anthropic|cohere|ollama|local), `model`, `promptTemplate`, `maxTokens`, `temperature`, `streaming` (bool), `systemPrompt`, `tools` (key_value_list), `outputFormat` (text|json|structured).
- **audit_log** — add `eventType`, `resourceType`, `resourceId`, `actorId`, `actorType`, `metadata`, `ipAddress`, `userAgent`, `severity`, `persistTo` (db|log|both).
- **template_render** — add `engine` (liquid|handlebars|mustache|erb|haml), `variables` (key_value_list), `filters` (key_value_list), `safeMode` (bool), `cacheCompiled` (bool), `strictVariables`.
- **i18n_translate** — add `key`, `locale`, `fallbackLocale`, `interpolations` (key_value_list), `scope`, `default`, `count` (for pluralization), `raiseOnMissing` (bool).
- **currency_convert** — add `fromCurrency`, `toCurrency`, `amount`, `rateSource` (ctx|config|provider|fixed), `provider` (select), `rounding` (select), `precision`, `cacheRates` (bool).
- **geolocation_lookup** — add `provider` (maxmind|ip2location|google|mapbox), `lookupKey` (ip|postal|address|coords), `fieldsToReturn` (key_value_list), `fallbackProvider`, `cacheResults`.
- **barcode_generate** — add `barcodeFormat` (code128|code39|ean13|ean8|upca|itf|codabar|qr), `width`, `height`, `margin`, `includeText` (bool), `outputFormat` (png|svg|jpg|base64), `textFont`.
- **qr_code_generate** — add `size`, `errorCorrection` (L|M|Q|H), `margin`, `colorDark`, `colorLight`, `logoExpression`, `outputFormat` (png|svg|base64|ascii).

### 5.16 process/validation (2 generators)

- **build_contract** — add `contractClass` (text), `attributeMappings` (key_value_list), `defaultValues` (key_value_list), `typeCoercion` (bool), `cacheContract` (bool), `validateOnBuild` (bool).
- **validate_contract** — add `contractRef` (ctx_var referring built contract), `permissionCheck` (select: none|policy|explicit), `onFailure` (select: raise|fail_track|collect_errors), `includeWarnings` (bool), `errorVar`, `strictMode`.

### 5.17 process/background (2 generators)

- **enqueue_job** — add `queueName` already; add `adapter` (sidekiq|resque|delayed_job|sneakers|active_job), `retrySet` (number), `priority`, `discardOn` (key_value_list), `retryOn`, `waitUntil`, `jobId` (text: explicit job id).
- **schedule_job** — add `scheduleType` (select: cron|interval|at_time|recurring), `cronExpression`, `intervalSeconds`, `runAt`, `timezone`, `recurrenceLimit`, `scheduler` (select: sidekiq_cron|whenever|clockwork|rails), `uniqueFor`.

---

## 6. JS configSchema Mechanics

### 6.1 Where fields live
- **process-step actions** (106 entries): `app/javascript/flowchart/constants/action_configs/<category>_actions.js`. Each entry has `configSchema: [...]`. Supported field types: `text`, `textarea`, `number`, `select`, `key_value_list`, `condition`, `inputs`, `outputs`, `steps`, `branches`, `error_handling`.
- **element-type schemas** (14 entries, `start`, `end`, `process`, `decision`, `join`, `loop`, `subflow`, `error_handler`, `timer`, …): `app/javascript/flowchart/constants/schemas.js` under `ELEMENT_SCHEMAS`. These use the `{fieldKey: fieldDef}` object shape (not array). `fieldDef` supports same types plus `tab` (general|io|steps|advanced), `control` (for segmented selects), `actionOptions` (for steps), `conditionOptions`, `dynamicOptions`, `min`, `max`.

### 6.2 Field definition grammar
```js
// action_configs shape (array of fields):
{
  key: "fieldName",       // required
  type: "select|text|...", // required
  label: "Display Label",  // required
  required: true|false,    // optional
  default: "...",          // optional
  placeholder: "...",      // optional (text/textarea/number)
  options: [{value, label}], // required for select
  visibleWhen: { field: "otherFieldKey", value: "..." } // optional
}

// schemas.js ELEMENT_SCHEMAS shape (object with keyed fields):
{
  fieldName: { type, label, ..., tab: "advanced" }
}
```

### 6.3 visibleWhen contract
Three forms supported:
- `{ field: "X", value: "a" }` — exact match
- `{ field: "X", values: ["a", "b"] }` — any-of match
- `{ field: "X", value: "" }` — matches default / unset

All three are honored by the property popup renderer.

### 6.4 Ruby mirror regeneration
After JS edits, run `bundle exec rake config_schemas:mirror` to regenerate `spec/support/config_schemas.rb`. CI runs `rake config_schemas:check` to detect drift. Every batch in the plan ends with a mirror regen step.

---

## 7. Testing Strategy

### 7.1 Per-generator spec additions
For each new field added:
1. **Positive case** — a test that passes the new field and asserts the generated Ruby includes the expected fragment.
2. **Enum rejection** — if the field has an enum, one test per invalid value asserting `validate_config` rejects it.
3. **Required-field omission** — if the field is required, assert `validate_config` surfaces an error.
4. **Interaction** — for fields with `visibleWhen`, a test that the dependent field is read when the parent has the matching value (and ignored when not).

Existing shared examples (`"a code generator"`) keep running.

### 7.2 Config-schema drift guard
The existing `rake config_schemas:check` task catches drift between JS and Ruby mirror.

### 7.3 Full-suite regression
After each batch, run `bundle exec rspec spec/services/code_generators/ --no-color --fail-fast`. Exit baseline must remain at **0 failures** across the 2388+ examples.

### 7.4 No integration-level smoke tests added
The existing per-category smoke tests already evaluate generated Ruby through `SourceAssembler` + `eval`. New config branches flow through them automatically.

---

## 8. Shipping Order (18 batches)

Batches run in the same numeric order as the 2026-04-17 plan to keep diffs reviewable:

| # | Category | Generators |
|---|---|---|
| 1 | flow_control | 14 |
| 2 | data_operations (collection ops) | 13 |
| 3 | data_operations (strings/parse/serialize/regex) | 6 |
| 4 | data_operations (math/date/type/misc) | 12 |
| 5 | model_operations (read-path) | 7 |
| 6 | model_operations (write-path) | 10 |
| 7 | security | 9 |
| 8 | communication | 4 |
| 9 | caching | 4 |
| 10 | concurrency | 2 |
| 11 | file_operations | 7 |
| 12 | human_workflow | 4 |
| 13 | realtime | 2 |
| 14 | resilience | 4 |
| 15 | response | 2 |
| 16 | scheduling_time | 3 |
| 17 | service_invocation | 1 |
| 18 | utility | 8 |
| 19 | validation | 2 |
| 20 | background | 2 |

Total: 20 batches, 116 generators.

Each batch ships as: Ruby generators + specs + JS schema + Ruby mirror regen + category spec pass.

---

## 9. Acceptance Criteria

A generator is "config-case enriched" when:
1. Its JS `configSchema` declares every new field from §5 for its category.
2. `validate_config` accepts/rejects every new enum/required field.
3. `generate_body` emits a real code branch for every new enum value (no stub fall-through).
4. Its rspec adds positive + invalid + interaction cases for every new field.
5. Generated code remains nil-safe (R1), error-wrapped where applicable (R2), timeout-bounded (R3), uses shared helpers (R4), canonical variable names (R5).
6. `spec/services/code_generators/` passes with 0 failures.
7. `rake config_schemas:check` passes (no drift).

A batch is done when every generator in the category meets per-generator criteria and the full generator suite stays green.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| 116 × ~5 fields × 3 layers → large volume | Parallel subagents per batch; per-generator independent |
| New fields break existing specs via config defaults | All new fields default to safest behavior; tests validate old contract still holds |
| JS/Ruby mirror drift mid-batch | Regen mirror at end of each batch; CI gate catches accidental drift |
| Field names collide with existing canonical names | §5 uses non-conflicting names; any overlap flagged in plan |
| Generated Ruby gets bloated when all new fields present | Fields only emit code when present in config (not when defaulted to nil) |
| Enum explosion (e.g., 8-value select) in UI | Accept; users pick from dropdown. Mitigation is field ordering + `visibleWhen`. |
