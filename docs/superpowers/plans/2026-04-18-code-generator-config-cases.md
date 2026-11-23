# Code Generator Config-Case Enrichment — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-04-18-code-generator-config-cases-design.md`
**Date:** 2026-04-18
**Mode:** Autonomous batch execution (per `feedback_autonomous_execution.md`). No mid-flight approval pauses. No commits (per AGENTS.md).

---

## Overview

20 sequential batches. Each batch touches 1–14 generators in a single category. Inside a batch, generators run as parallel subagents (one subagent per generator — they are independent). After each batch:

1. Regenerate Ruby mirror: `bundle exec rake config_schemas:mirror`
2. Run category spec: `bundle exec rspec spec/services/code_generators/element_types/<category>/`
3. Run smoke: `bundle exec rspec spec/services/code_generators/ --fail-fast`
4. Report results in main conversation
5. Proceed to next batch immediately

---

## Per-Generator Template (applied to every generator)

Every subagent executes exactly these steps for its assigned generator:

1. **Read** `app/services/code_generators/element_types/<path>/<name>_generator.rb`.
2. **Read** `spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb`.
3. **Identify** the JS config file: `app/javascript/flowchart/constants/action_configs/<category>_actions.js` for process steps, or `app/javascript/flowchart/constants/schemas.js` for element-type generators.
4. **Identify** the target new fields from §5.x of the spec (matching the generator's category).
5. **Update `validate_config(cfg)`** — accept the new field, reject invalid enum values, require fields per spec.
6. **Update `generate_body`** — read the new config via `config[...]` or `fetch_enum`/`fetch_with_default` helpers; emit a code branch per enum value; keep nil-safety (R1), errorWrapper (R2), timeout (R3), shared helpers (R4), canonical variable names (R5).
7. **Update constants** (e.g., `ACTIONS`, `STRATEGIES`) when adding an enum.
8. **Update `self.sample_input`** if it's misleading with new fields.
9. **Update spec** — add one example per new enum value, one example per invalid value, one example per required-field omission, one interaction example per `visibleWhen`.
10. **Update JS `configSchema`** — add field definition(s) in the proper format (array entry or object-keyed entry for schemas.js).
11. **Do NOT** edit `spec/support/config_schemas.rb` directly — the batch-end step regenerates it.

**Ctx access rule (per `feedback_ctx_access_pattern.md`):** All generated code uses `ctx[:key]` / `ctx[:key] = value` exclusively — no keyword destructuring, no `ctx.fetch`, no `ctx.dig` at the signature level.

**No backward compat (per AGENTS.md):** If a field rename makes the name clearer, do it across all three layers in one change.

---

## Batch 1 — flow_control (14 generators)

**Generators:** `start`, `end`, `process`, `decision`, `join`, `loop`, `subflow`, `error_handler`, `timer`, `switch`, `fork`, `parallel_for_each`, `saga`, `signal_wait`, `transaction`.

Spec reference: §5.1.

> Note: `start` and `subflow` have thin `generate_body` (metadata-only). We still enrich the `configSchema` for UI completeness, update spec to verify schema changes, but avoid adding runtime branches unless the field maps to something concrete.

- [ ] Task 1.1: `start` — add fields per §5.1 (triggerScope, authRequired, rateLimitPerMinute, eventFilter). JS edit in `schemas.js`.
- [ ] Task 1.2: `end` — add cacheControl, contentType, cookieOperations, location, triggerWorkflowOnComplete. JS edit in `schemas.js`.
- [ ] Task 1.3: `process` — add isolateCtx, onStepFailure. JS edit in `schemas.js`.
- [ ] Task 1.4: `decision` — add firstMatchOnly, defaultBranchIndex. JS edit in `schemas.js`.
- [ ] Task 1.5: `switch` — add caseInsensitive, allowFallthrough. JS edit in `schemas.js` (if present) or `action_registry.js`.
- [ ] Task 1.6: `loop` — add breakCondition, accumulatorVariable, skipCondition. JS edit in `schemas.js`.
- [ ] Task 1.7: `fork` — add maxParallelism, threadPoolName. JS edit in `schemas.js`.
- [ ] Task 1.8: `join` — add additional joinStrategy enum values (wait_any, wait_n), requiredCount, timeoutSeconds. JS edit in `schemas.js`.
- [ ] Task 1.9: `parallel_for_each` — add maxConcurrency, orderedResults, errorAggregation, batchSize. JS edit in `schemas.js`.
- [ ] Task 1.10: `saga` — add compensationOrder, onCompensationFailure, isolationLevel. JS edit in `schemas.js`.
- [ ] Task 1.11: `signal_wait` — add signalFilter, cleanupOnTimeout, timeoutBehavior. JS edit in `schemas.js`.
- [ ] Task 1.12: `timer` — add maxWaitSeconds, pollIntervalSeconds, jitter. JS edit in `schemas.js`.
- [ ] Task 1.13: `transaction` — add isolationLevel, timeoutSeconds, lockTimeoutSeconds, rollbackOnAnyError. JS edit in `schemas.js`.
- [ ] Task 1.14: `error_handler` — add errorClassPatterns, notifyOnError, captureBacktrace. JS edit in `schemas.js`.
- [ ] Task 1.15: `subflow` — add subflowId, inputMapping, outputMapping, runMode. JS edit in `schemas.js`.

Batch-end verification:
- `bundle exec rake config_schemas:mirror`
- `bundle exec rspec spec/services/code_generators/element_types/`
- Expected: 0 failures, example count increased.

---

## Batch 2 — data_operations (collection ops, 13 generators)

**Generators:** `map_collection`, `filter_collection`, `sort_collection`, `group_collection`, `partition_collection`, `chunk_collection`, `find_in_collection`, `uniq_collection`, `flatten_collection`, `zip_collections`, `reduce_collection`, `pluck_fields`, `any_all_none_check`.

Spec reference: §5.2 bullets for each.

- [ ] Task 2.1: `map_collection` — parallel, compactResult, preserveNilElements, indexAwareMapping.
- [ ] Task 2.2: `filter_collection` — rejectMode, nilHandling, secondaryFilter.
- [ ] Task 2.3: `sort_collection` — sortFields (multi-key), nullsFirst, stable, locale.
- [ ] Task 2.4: `group_collection` — groupByExpression, includeCount, sortGroups.
- [ ] Task 2.5: `partition_collection` — partitionField, limit, includeStats.
- [ ] Task 2.6: `chunk_collection` — chunkMode, chunkPredicate, includeRemainder, strict.
- [ ] Task 2.7: `find_in_collection` — returnMode, searchStrategy, defaultValue.
- [ ] Task 2.8: `uniq_collection` — uniqBy, keepStrategy.
- [ ] Task 2.9: `flatten_collection` — depth, removeNilElements, preserveStructure.
- [ ] Task 2.10: `zip_collections` — fillValue, zipStrategy, resultShape.
- [ ] Task 2.11: `reduce_collection` — initialValue, accumulatorType.
- [ ] Task 2.12: `pluck_fields` — fields (multi), flatten, includeSourceIndex, renameMapping.
- [ ] Task 2.13: `any_all_none_check` — predicateType, valueList.

JS edits in `data_actions.js`. Batch-end verification same as Batch 1 for `data_operations/`.

---

## Batch 3 — data_operations (strings/parse/serialize/regex, 6 generators)

**Generators:** `format_string`, `parse_data`, `serialize_data`, `regex_extract`, `string_manipulate`, `base64_encode_decode`.

- [ ] Task 3.1: `format_string` — formatStyle (ruby_interpolation|printf|mustache|liquid), fallbackOnMissing, escapeHtml.
- [ ] Task 3.2: `parse_data` — format (json|csv|xml|yaml|toml|properties), csvHeaders, csvDelimiter, xmlRoot, strictMode, symbolizeKeys.
- [ ] Task 3.3: `serialize_data` — format, pretty, includeRoot, excludeNils, jsonMaxDepth.
- [ ] Task 3.4: `regex_extract` — regexFlags, captureGroups, returnType, fallbackValue.
- [ ] Task 3.5: `string_manipulate` — operations (sequence), regexEscape, encoding.
- [ ] Task 3.6: `base64_encode_decode` — urlSafe, stripPadding, inputEncoding, lineWidth.

JS edits in `data_actions.js`. Batch-end verification.

---

## Batch 4 — data_operations (math/date/type/misc, 12 generators)

**Generators:** `calculate`, `math_operation`, `type_cast`, `date_time_calc`, `generate_id`, `assign_value`, `coalesce_value`, `compare_data`, `hash_manipulate`, `log`, `map_value`, `merge_data`, `transform`.

- [ ] Task 4.1: `calculate` — emptyCollectionDefault, ignoreNils, precision, roundingMode.
- [ ] Task 4.2: `math_operation` — extended operation enum (modulo/power/abs/floor/ceil/round), divideByZero.
- [ ] Task 4.3: `type_cast` — extended targetType (big_decimal/rational/complex/symbol/time/date_time), onCastFailure.
- [ ] Task 4.4: `date_time_calc` — inputFormat, outputFormat, businessDays, timezone, calendarProvider.
- [ ] Task 4.5: `generate_id` — idType (uuid/uuid_v7/ulid/snowflake/nanoid/hash), length, prefix, separator, uppercase.
- [ ] Task 4.6: `assign_value` — extended valueType (ctx_ref/env_var/credential/random).
- [ ] Task 4.7: `coalesce_value` — operandList, returnFirstNonBlank vs returnFirstNonNil, blankDefinition.
- [ ] Task 4.8: `compare_data` — comparisonType, ignoreKeys, caseInsensitive, numericTolerance.
- [ ] Task 4.9: `hash_manipulate` — extended operation enum (pick/omit/deep_merge/deep_dup/symbolize_keys/stringify_keys/transform_keys/transform_values/compact/invert).
- [ ] Task 4.10: `log` — logger, tags, includeBacktrace, structured, maxMessageLength.
- [ ] Task 4.11: `map_value` — fallbackStrategy, multiMatch, caseSensitive.
- [ ] Task 4.12: `merge_data` — mergeStrategy, arrayMergeMode, onConflict.
- [ ] Task 4.13: `transform` — extended transformType (rename_fields/remove_fields/add_computed_fields/flatten_nested).

JS edits in `data_actions.js`. Batch-end verification.

---

## Batch 5 — model_operations (read-path, 7 generators)

**Generators:** `find_model`, `query_models`, `count_records`, `check_existence`, `aggregate_query`, `pluck_fields`, `batch_operation`.

- [ ] Task 5.1: `find_model` — extended findStrategy (find_by_bang/first/last/take), includes, lock, readonly.
- [ ] Task 5.2: `query_models` — select, distinct, groupBy, having, includes, preload, lock, readonly, joinConditions.
- [ ] Task 5.3: `count_records` — distinct, groupBy, conditions.
- [ ] Task 5.4: `check_existence` — negated, withTransaction.
- [ ] Task 5.5: `aggregate_query` — aggregations (list), groupBy, having, resultFormat.
- [ ] Task 5.6: `pluck_fields` (model variant; different from data_operations pluck_fields) — distinct, limit, orderBy.
- [ ] Task 5.7: `batch_operation` — batchSize, operationType, progressVar, errorCollection.

JS edits in `model_actions.js`. Batch-end verification.

---

## Batch 6 — model_operations (write-path, 10 generators)

**Generators:** `new_model`, `save_model`, `update_model`, `destroy_model`, `upsert_model`, `clone_model`, `bulk_import`, `soft_delete_model`, `transition_state`, `raw_sql_query`.

- [ ] Task 6.1: `new_model` — attributes, skipValidation, customerScoped, associations.
- [ ] Task 6.2: `save_model` — validate, touch, context, returnUpdated.
- [ ] Task 6.3: `update_model` — updateStrategy, runCallbacks, returnChanges, lockVersion.
- [ ] Task 6.4: `destroy_model` — cascade, dependent, confirmWithPassword.
- [ ] Task 6.5: `upsert_model` — uniqueBy, onConflict, returning, timestamps.
- [ ] Task 6.6: `clone_model` — excludeFields, overrideFields, cloneAssociations, depth.
- [ ] Task 6.7: `bulk_import` — batchSize, validate, skipDuplicates, onDuplicateKey, returning, timestamps.
- [ ] Task 6.8: `soft_delete_model` — deletedAtField, deletedByField, soft_delete_strategy.
- [ ] Task 6.9: `transition_state` — event, fromState, toState, guardCondition, persistImmediately, auditTrail.
- [ ] Task 6.10: `raw_sql_query` — bindings, resultShape, sanitizeInput.

JS edits in `model_actions.js`. Batch-end verification.

---

## Batch 7 — security (9 generators)

**Generators:** `authenticate`, `authorize`, `encrypt_data`, `decrypt_data`, `generate_token`, `verify_token`, `hash_data`, `mask_data`, `sanitize_input`.

- [ ] Task 7.1: `authenticate` — authMethod, credentialSource, tokenAlgorithm, maxAttempts, lockoutSeconds.
- [ ] Task 7.2: `authorize` — extended authType (ability_check/multi_role/attribute_based), onFailure.
- [ ] Task 7.3: `encrypt_data` — algorithm enum, keySource, aad, encoding, deriveKeyFrom.
- [ ] Task 7.4: `decrypt_data` — mirror encrypt, verifyAuth, onFailure.
- [ ] Task 7.5: `generate_token` — tokenType, issuer, audience, notBefore, expiresIn, claims, keyId, secretSource.
- [ ] Task 7.6: `verify_token` — algorithmAllowlist, verifyIssuer, verifyAudience, leewaySeconds, requiredClaims, onFailure.
- [ ] Task 7.7: `hash_data` — algorithm enum, cost, salt, iterations, pepper, encoding.
- [ ] Task 7.8: `mask_data` — maskType, visibleStart, visibleEnd, maskChar, preserveFormat, regexPattern.
- [ ] Task 7.9: `sanitize_input` — sanitizer, allowedTags, allowedAttributes, stripTags, removeNullBytes, maxLength.

JS edits in `security_actions.js`. Batch-end verification.

---

## Batch 8 — communication (4 generators)

**Generators:** `api_call`, `send_email`, `send_webhook`, `notify`.

- [ ] Task 8.1: `api_call` — followRedirects, maxRedirects, verifySsl, queryParams, responseParseKey, retryOnStatus, acceptEncoding, userAgent, connectTimeout/readTimeout, cookies, bodyFormat.
- [ ] Task 8.2: `send_email` — cc, bcc, replyTo, from, htmlBody, textBody, attachments, headers, priority, trackOpens.
- [ ] Task 8.3: `send_webhook` — hmacAlgorithm, signatureHeader, idempotencyKey, retryPolicy, deadLetterVar, contentType.
- [ ] Task 8.4: `notify` — per-channel fields (Slack/SMS/Push/In-App), fallbackChannels.

JS edits in `communication_actions.js`. Batch-end verification.

---

## Batch 9 — caching (4 generators)

- [ ] Task 9.1: `cache_read` — storeName, namespace, decompressOnRead, versionCheck, onMiss.
- [ ] Task 9.2: `cache_write` — compress, raw, race_condition_ttl, namespace, version, storeName, tags.
- [ ] Task 9.3: `cache_fetch` — raceConditionTtl, forceRefresh, skipNilCache, versionKey, fallbackErrorStrategy.
- [ ] Task 9.4: `cache_delete` — scope, tags, confirmPattern.

JS edits in `caching_actions.js`. Batch-end verification.

---

## Batch 10 — concurrency (2 generators)

- [ ] Task 10.1: `acquire_lock` — lockType, acquireTimeoutSeconds, lockKey, holderIdentity, retryStrategy, heartbeatSeconds, onConflict.
- [ ] Task 10.2: `release_lock` — lockType, lockKey, holderIdentity, onMissing, releaseAll.

JS edits in `concurrency_actions.js`. Batch-end verification.

---

## Batch 11 — file_operations (7 generators)

- [ ] Task 11.1: `download_file` — destination, maxSizeBytes, followRedirects, verifySsl, validateChecksum, chunked.
- [ ] Task 11.2: `upload_file` — service, maxSizeBytes, allowedTypes, public, metadata.
- [ ] Task 11.3: `parse_csv` — encoding, delimiter, quoteChar, headerRow, skipRows, colTypes.
- [ ] Task 11.4: `generate_csv` — encoding, delimiter, headerRow, quoteStrings, includeBom, rowProcessor.
- [ ] Task 11.5: `compress_files` — format, compressionLevel, passwordProtect, includeHidden, preservePermissions.
- [ ] Task 11.6: `decompress_files` — format, password, targetDir, pathTraversalGuard, overwrite.
- [ ] Task 11.7: `generate_file` — format, per-format template fields, outputDestination.

JS edits in `file_actions.js`. Batch-end verification.

---

## Batch 12 — human_workflow (4 generators)

- [ ] Task 12.1: `approval_gate` — mode, requiredCount, approverGroup, timeoutBehavior, delegationAllowed, commentsRequired.
- [ ] Task 12.2: `assign_task` — priority, dueAtExpression, taskType, notificationChannels, checklistItems, attachments.
- [ ] Task 12.3: `escalation` — escalationPolicy, escalationLevels, maxEscalations, notificationChannels, resetOnAck.
- [ ] Task 12.4: `user_input_request` — formFields, validationRules, maxResponseTime, notificationChannel, resumeBehavior.

JS edits in `human_workflow_actions.js`. Batch-end verification.

---

## Batch 13 — realtime (2 generators)

- [ ] Task 13.1: `broadcast` — per-type fields (Turbo turboFrame/morphStrategy, Action Cable channelClass/signedStreamName/filterCallback).
- [ ] Task 13.2: `publish_event` — eventBus, partitionKey, idempotencyKey, priority, retryPolicy, schemaVersion.

JS edits in `realtime_actions.js`. Batch-end verification.

---

## Batch 14 — resilience (4 generators)

- [ ] Task 14.1: `circuit_breaker` — failureThreshold, successThreshold, halfOpenTrialRequests, resetTimeoutSeconds, windowSizeSeconds, jitter.
- [ ] Task 14.2: `idempotency_check` — keyStrategy, ttlSeconds, storeName, onDuplicate.
- [ ] Task 14.3: `rate_limiter` — algorithm, capacity, refillRate, burstAllowance, onExceed.
- [ ] Task 14.4: `retry_with_backoff` — backoffStrategy, initialDelay, maxDelay, maxRetries, retryableErrors, onExhausted.

JS edits in `resilience_actions.js`. Batch-end verification.

---

## Batch 15 — response (2 generators)

- [ ] Task 15.1: `render_response` — extended responseFormat (xml/text/csv/file/stream), headers, contentType, charset, etag, lastModified.
- [ ] Task 15.2: `redirect_response` — statusCode enum, preserveQueryParams, addReferrer, jsonApiFormat.

JS edits in `response_actions.js`. Batch-end verification.

---

## Batch 16 — scheduling_time (3 generators)

- [ ] Task 16.1: `business_hours_check` — schedule, holidays, timezone, resultMode.
- [ ] Task 16.2: `deadline_check` — deadlineExpression, referenceTime, gracePeriodSeconds, behaviorOnBreach, breachedVar.
- [ ] Task 16.3: `timezone_convert` — sourceTimezone, targetTimezone, preserveLocalTime, outputFormat, dstBehavior.

JS edits in `scheduling_actions.js`. Batch-end verification.

---

## Batch 17 — service_invocation (1 generator)

- [ ] Task 17.1: `invoke_service` — serviceClass, invocationStyle, methodName, args, kwargs, resultVar, definedGuard, onMissing.

JS edits in `service_actions.js`. Batch-end verification.

---

## Batch 18 — utility (8 generators)

- [ ] Task 18.1: `ai_inference` — provider, model, promptTemplate, maxTokens, temperature, streaming, systemPrompt, tools, outputFormat.
- [ ] Task 18.2: `audit_log` — eventType, resourceType, resourceId, actorId, actorType, metadata, ipAddress, userAgent, severity, persistTo.
- [ ] Task 18.3: `template_render` — engine, variables, filters, safeMode, cacheCompiled, strictVariables.
- [ ] Task 18.4: `i18n_translate` — key, locale, fallbackLocale, interpolations, scope, default, count, raiseOnMissing.
- [ ] Task 18.5: `currency_convert` — fromCurrency, toCurrency, amount, rateSource, provider, rounding, precision, cacheRates.
- [ ] Task 18.6: `geolocation_lookup` — provider, lookupKey, fieldsToReturn, fallbackProvider, cacheResults.
- [ ] Task 18.7: `barcode_generate` — barcodeFormat, width, height, margin, includeText, outputFormat, textFont.
- [ ] Task 18.8: `qr_code_generate` — size, errorCorrection, margin, colorDark, colorLight, logoExpression, outputFormat.

JS edits in `utility_actions.js`. Batch-end verification.

---

## Batch 19 — validation (2 generators)

- [ ] Task 19.1: `build_contract` — contractClass, attributeMappings, defaultValues, typeCoercion, cacheContract, validateOnBuild.
- [ ] Task 19.2: `validate_contract` — contractRef, permissionCheck, onFailure, includeWarnings, errorVar, strictMode.

JS edits in `validation_actions.js`. Batch-end verification.

---

## Batch 20 — background (2 generators)

- [ ] Task 20.1: `enqueue_job` — adapter, retrySet, priority, discardOn, retryOn, waitUntil, jobId.
- [ ] Task 20.2: `schedule_job` — scheduleType, cronExpression, intervalSeconds, runAt, timezone, recurrenceLimit, scheduler, uniqueFor.

JS edits in `background_actions.js`. Batch-end verification.

---

## Final Pass

After Batch 20:

- [ ] Run `bundle exec rake config_schemas:mirror` (one last regen).
- [ ] Run `bundle exec rspec spec/services/code_generators/ --no-color` — expect **0 failures** across the full suite.
- [ ] Report example count delta (from baseline 2388).
- [ ] Summarize: total fields added, generators touched, JS files modified, mirror entries count, delta lines of Ruby/JS/spec.
- [ ] Do NOT commit. Leave for user review.

---

## Task Ordering Policy

- Execute batches sequentially (1 → 20).
- Within each batch, dispatch generators in parallel via subagents using the per-generator template. Each subagent touches exactly its generator's trio (Ruby + spec + JS entry).
- After all subagents in a batch return, regenerate mirror + run category + full-suite tests. If failures: fix them before next batch. If fixing takes > 1 retry per generator, halt and report.

## Safety Rails

- Any spec failure stops only the containing batch, not the whole plan — fix, then continue.
- If a generator already has a field from §5 (earlier enrichment overlap), skip that field and note it in the batch summary.
- Never edit `spec/support/config_schemas.rb` by hand — always use the rake task.
- Never edit JS imports / exports / registry. Only mutate the `configSchema: [...]` array (or the equivalent element-type schema object in schemas.js).
