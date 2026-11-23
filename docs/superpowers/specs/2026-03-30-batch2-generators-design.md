# Batch 2 Generators Design — Caching, Model Ops, Security, File Ops

## Overview

Add 6 new step action generators across 4 categories: caching (new), model_operations, security, file_operations. Follows the same `BaseGenerator` pattern as the existing 39 generators.

## Generators

### 1. CacheRead

- **Category**: `caching` (new)
- **Config**: `cacheKey` (string), `targetVariable` (string), `ttl` (integer seconds, optional), `fallbackExpression` (string, optional Ruby expression)
- **Generated code**:
  - With fallback + ttl: `ctx[:target] = Rails.cache.fetch("key", expires_in: 300) { expression }`
  - With fallback, no ttl: `ctx[:target] = Rails.cache.fetch("key") { expression }`
  - Without fallback: `ctx[:target] = Rails.cache.read("key")`
- **Validation**: cacheKey required.
- **Example**: `ctx[:data] = Rails.cache.fetch("user_42", expires_in: 300) { User.find(42) }\ntrue`

### 2. CacheWrite

- **Category**: `caching`
- **Config**: `cacheKey` (string), `sourceVariable` (string), `ttl` (integer seconds, optional), `action` (enum: write, delete; default write)
- **Generated code**:
  - write with ttl: `Rails.cache.write("key", ctx[:source], expires_in: 300)`
  - write without ttl: `Rails.cache.write("key", ctx[:source])`
  - delete: `Rails.cache.delete("key")`
- **Validation**: cacheKey required. action must be write or delete.
- **Example**: `Rails.cache.write("user_42", ctx[:user], expires_in: 600)\ntrue`

### 3. TransitionState

- **Category**: `model_operations`
- **Config**: `stateField` (string, default "status"), `targetState` (string), `allowedFromStates` (array of strings, optional)
- **Generated code**:
  - With allowed states: validates current state, then `ctx[:model].update!(field => "target")`
  - Without allowed states: `ctx[:model].update!(field => "target")` unconditionally
- **Validation**: targetState required.
- **Example**: `current = ctx[:model].status\nraise "Invalid transition" unless ["draft", "review"].include?(current)\nctx[:model].update!(status: "published")\ntrue`

### 4. BatchOperation

- **Category**: `model_operations`
- **Config**: `sourceVariable` (string), `batchSize` (integer, default 100), `operation` (enum: each, update_all, destroy_all), `fieldAssignments` (hash, for update_all)
- **Generated code**:
  - each: `ctx[:source].find_each(batch_size: 100) { |record| record.save }`
  - update_all: `ctx[:source].in_batches(of: 100).update_all(field: "value")`
  - destroy_all: `ctx[:source].in_batches(of: 100).destroy_all`
- **Validation**: sourceVariable required. operation must be in allowed list.
- **Example**: `ctx[:items].in_batches(of: 100).update_all(status: "archived")\ntrue`

### 5. EncryptData

- **Category**: `security`
- **Config**: `sourceVariable` (string), `targetVariable` (string), `action` (enum: encrypt, decrypt)
- **Generated code**:
  - encrypt: `encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0..31])\nctx[:target] = encryptor.encrypt_and_sign(ctx[:source].to_s)`
  - decrypt: `encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0..31])\nctx[:target] = encryptor.decrypt_and_verify(ctx[:source])`
- **Validation**: sourceVariable required. action must be encrypt or decrypt.
- **Example**: `encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0..31])\nctx[:encrypted] = encryptor.encrypt_and_sign(ctx[:ssn].to_s)\ntrue`

### 6. DownloadFile

- **Category**: `file_operations`
- **Config**: `url` (string, static URL), `urlVariable` (string, ctx variable holding URL — used when url is blank), `targetVariable` (string)
- **Generated code**:
  - Static url: `ctx[:target] = URI.open("https://...").read`
  - Dynamic url: `ctx[:target] = URI.open(ctx[:url_var]).read`
- **Validation**: either url or urlVariable required.
- **Example**: `ctx[:file_content] = URI.open("https://example.com/data.csv").read\ntrue`

## File Structure

New files (12 total):

```
app/services/code_generators/element_types/process/caching/cache_read_generator.rb
app/services/code_generators/element_types/process/caching/cache_write_generator.rb
app/services/code_generators/element_types/process/model_operations/transition_state_generator.rb
app/services/code_generators/element_types/process/model_operations/batch_operation_generator.rb
app/services/code_generators/element_types/process/security/encrypt_data_generator.rb
app/services/code_generators/element_types/process/file_operations/download_file_generator.rb
spec/services/code_generators/element_types/process/caching/cache_read_generator_spec.rb
spec/services/code_generators/element_types/process/caching/cache_write_generator_spec.rb
spec/services/code_generators/element_types/process/model_operations/transition_state_generator_spec.rb
spec/services/code_generators/element_types/process/model_operations/batch_operation_generator_spec.rb
spec/services/code_generators/element_types/process/security/encrypt_data_generator_spec.rb
spec/services/code_generators/element_types/process/file_operations/download_file_generator_spec.rb
```

## Testing

Same pattern as Batch 1: `it_behaves_like "a code generator"` plus specific tests for each config variant and validation.
