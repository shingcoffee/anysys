# Generator Error Handling Removal Design

## Overview

Refactor all code generators under `app/services/code_generators/` to remove error handling from generated Trailblazer Activity code. Error handling is centralized in `dynamic_controller.rb`.

## Background

- `ctx[:bound_entity]` provides model/contract derivation at runtime
- `EntityEntry.build_for(ctx[:bound_entity])` creates entity-specific model class
- `EntityEntryContract.build_for(ctx[:bound_entity])` creates entity-specific contract class
- Controller wraps activity execution in transaction and handles all failures

## Changes

### Generators with `raise` Statements to Modify

| Generator | Current Pattern | New Behavior |
|-----------|----------------|--------------|
| `build_contract_generator.rb` | `raise NameError` if contract class undefined | Remove check (trust class loader) |
| `validate_contract_generator.rb` | `raise` on failure, `raise "Unauthorized"`, `raise ArgumentError` | `return false` |
| `enqueue_job_generator.rb` | `raise NameError` if job class undefined | Remove check |
| `schedule_job_generator.rb` | `raise NameError`, `raise ArgumentError` for invalid cron | Remove checks |
| `cache_read_generator.rb` | `raise "cache miss"` option | Return nil only |
| `cache_fetch_generator.rb` | `raise` in fallback error strategy | Return nil only |
| `cache_delete_generator.rb` | `raise` if pattern matches too many keys | Skip silently |
| `send_email_generator.rb` | `ERROR_STRATEGIES` with raise | Remove raise option |
| `calculate_generator.rb` | `raise` for empty collection | Return nil |
| `merge_data_generator.rb` | `raise` for duplicate keys | Overwrite (last wins) |
| `compress_files_generator.rb` | `ERROR_STRATEGIES` with raise | Remove raise option |
| `parse_csv_generator.rb` | `ERROR_STRATEGIES` with raise | Remove raise option |
| `bulk_import_generator.rb` | `insert_all!` (raises) option | Use non-raising variants |
| `parallel_for_each_generator.rb` | `raise thread_err` | Collect errors, continue |
| `destroy_model_generator.rb` | `raise "password mismatch"` | `return false` |

### Config Options to Remove

| Generator | Fields to Remove |
|-----------|-----------------|
| `validate_contract_generator.rb` | `onFailure`, `strictMode`, `errorVar`, `includeWarnings` |
| `cache_read_generator.rb` | `onMissBehavior` |
| `cache_fetch_generator.rb` | `fallbackErrorStrategy` |
| `send_email_generator.rb` | `errorStrategy` |
| `compress_files_generator.rb` | `errorStrategy` |
| `parse_csv_generator.rb` | `errorStrategy` |
| `bulk_import_generator.rb` | `raise` from `onDuplicateKey` enum |
| `parallel_for_each_generator.rb` | `errorAggregation` |
| `merge_data_generator.rb` | `error` from `onConflict` enum |
| `calculate_generator.rb` | `error` from `onEmpty` enum |

### JS Schema Files to Update

- `validation_actions.js` - remove `onFailure`, `strictMode`, `errorVar`, `includeWarnings`
- `caching_actions.js` - remove `onMissBehavior`, `fallbackErrorStrategy`
- `communication_actions.js` - remove `errorStrategy`
- `file_actions.js` - remove `errorStrategy` from compress/parse_csv
- `model_actions.js` - remove `raise` from `onDuplicateKey` enum
- `data_actions.js` - remove error options from calculate, merge_data

Note: `parallel_for_each` is an element type generator, not an action. Its config is in the Ruby generator only (no JS schema entry).

### Post-Change Steps

1. Run `rake config_schemas:mirror` to regenerate Ruby schema mirror
2. Update generator specs to expect new behavior
3. Run full test suite

## Default Behaviors After Removal

| Scenario | Behavior |
|----------|----------|
| Contract validation fails | `return false`, errors via `contract.errors` |
| Permission check fails | `return false` |
| Cache miss | Return `nil` |
| Email send fails | `return false` |
| File operation fails | `return false` |
| Bulk import duplicate | Skip or update |
| Parallel iteration error | Collect in results, continue |
| Merge data duplicate key | Overwrite |
| Calculate on empty | Return `nil` |
| Job class not defined | Runtime error (controller catches) |
| Password mismatch | `return false` |

## Controller Error Handling

`dynamic_controller.rb` already handles all failures:

```ruby
result = ActivityTracer.new(@flowchart).call(ctx)
raise ActiveRecord::Rollback unless result.success?
# renders error response if !result.success?
```

## Migration Impact

- Existing flowcharts with `raise` options use new default behavior
- No database migrations
- No backward compatibility shims
