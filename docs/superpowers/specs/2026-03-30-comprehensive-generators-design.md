# Comprehensive Code Generators Design — Structural Elements, Model Ops, Data Ops, Security, Concurrency, Service Invocation

## Overview

Add 20 new generators to achieve comprehensive business logic coverage: 5 new structural element types and 15 new step action generators across 6 categories (4 existing + 2 new). Follows the existing `BaseGenerator` pattern with purely additive changes (Approach 1 — no refactoring).

**Single spec, phased implementation plans (4 phases).**

### Scope Summary

| Category | New Generators | Running Total |
|----------|---------------|---------------|
| Structural Elements | 5 new | 14 (was 9) |
| Model Operations | 4 new | 11 (was 7) |
| Data Operations | 6 new | 16 (was 10) |
| Security | 3 new | 5 (was 2) |
| Concurrency (new) | 1 new | 1 |
| Service Invocation (new) | 1 new | 1 |
| **Total** | **20 new** | **61 generators** |

---

## Part 1: New Structural Elements (5)

New flowchart node types under `element_types/`, following the same pattern as Decision, Fork/Join, Loop, etc.

### 1.1 Switch

Multi-way branching — routes to one of N named paths based on a value match.

- **Config:** `sourceVariable` (string), `cases` (array of `{ "value": "x", "label": "Case X" }`), `defaultLabel` (string, optional)
- **Generated code:**
  ```ruby
  _switch_val = ctx[:status].to_s
  case _switch_val
  when "draft" then :draft_path
  when "review" then :review_path
  when "published" then :published_path
  else :default_path
  end
  ```
- **Differs from Decision:** Decision is binary (true/false). Switch routes to N named outputs.
- **Validation:** sourceVariable required, cases must be non-empty array with `value` keys.

### 1.2 Saga

Compensation pattern — each step registers a rollback action. If any step fails, compensating actions execute in reverse order.

- **Config:** `compensationMode` (enum: `reverse_all`, `reverse_from_failure`; default `reverse_all`), `compensationTimeout` (integer seconds, optional)
- **Generated code:**
  ```ruby
  _compensations = []
  begin
    # Steps execute here, each calling:
    # _compensations << -> { <undo_code> }
    true
  rescue => e
    _compensations.reverse_each { |comp| comp.call rescue nil }
    raise e
  end
  ```
- **Usage:** Wraps a section of the flowchart. Each child step inside the Saga can optionally declare a `compensationAction` config field — a string containing the Ruby code to undo that step's work (e.g., `"ctx[:order].update!(status: 'cancelled')"` to reverse a status change). When a step executes successfully inside a Saga, its `compensationAction` (if present) is pushed onto the compensations stack. If any step fails, the Saga pops and executes compensations in reverse order.
- **Validation:** At least one child step required.

### 1.3 SignalWait

Pauses workflow execution until an external signal/event is received.

- **Config:** `signalName` (string), `waitMode` (enum: `pause_and_resume`, `poll`; default `pause_and_resume`), `timeoutSeconds` (integer, optional), `timeoutAction` (enum: `fail`, `continue`; default `fail`)
- **Generated code (pause_and_resume):**
  ```ruby
  signal_key = "workflow_signal:#{ctx[:_workflow_id]}:approval_signal"
  Rails.cache.write(signal_key, { status: "waiting", since: Time.current })
  # Workflow engine suspends here; resumes when signal received
  signal_data = Rails.cache.read(signal_key)
  ctx[:signal_result] = signal_data[:payload] if signal_data
  true
  ```
- **Generated code (poll):**
  ```ruby
  signal_key = "workflow_signal:#{ctx[:_workflow_id]}:data_ready"
  deadline = Time.current + 300
  loop do
    signal_data = Rails.cache.read(signal_key)
    break if signal_data&.dig(:status) == "received"
    raise "Signal timeout" if Time.current > deadline
    sleep 2
  end
  ctx[:signal_result] = signal_data[:payload]
  true
  ```
- **Use cases:** Human approval gates, webhook callbacks, waiting for async processing.
- **Validation:** signalName required.

### 1.4 ParallelForEach

Iterates over a collection and processes each item concurrently.

- **Config:** `sourceVariable` (string), `itemVariable` (string), `concurrency` (integer, default 5), `resultVariable` (string, optional)
- **Generated code:**
  ```ruby
  _results = Concurrent::Array.new
  _source = ctx[:orders]
  _source.each_slice(5).flat_map do |batch|
    batch.map do |item|
      Thread.new do
        ctx_copy = ctx.slice(:_workflow_id, :customer_id)
        ctx_copy[:order] = item
        # Execute child steps with ctx_copy
        _results << ctx_copy[:result]
      end
    end.each(&:join)
  end
  ctx[:processed_results] = _results.to_a
  true
  ```
- **Differs from Loop:** Loop is sequential. ParallelForEach uses threads with configurable concurrency.
- **Validation:** sourceVariable required.

### 1.5 Transaction

Wraps a section of steps in a database transaction.

- **Config:** `isolationLevel` (enum: `read_committed`, `repeatable_read`, `serializable`; optional), `requiresNew` (boolean, default false)
- **Generated code (default):**
  ```ruby
  ActiveRecord::Base.transaction do
    # Child steps execute here
  end
  ```
- **Generated code (with options):**
  ```ruby
  ActiveRecord::Base.transaction(isolation: :serializable, requires_new: true) do
    # Child steps execute here
  end
  ```
- **Differs from SaveModel:** SaveModel wraps individual saves. Transaction wraps arbitrary groups of steps.
- **Validation:** None required (all config optional).

---

## Part 2: New Step Actions — Model Operations (4)

Under `element_types/process/model_operations/`.

### 2.1 CheckExistence

Checks whether records matching criteria exist.

- **Category:** `model_operations`
- **Config:** `modelName` (string), `checkMethod` (enum: `exists`, `any`, `none`; default `exists`), `conditions` (hash, optional), `conditionVariable` (string, optional), `targetVariable` (string)
- **Generated code (exists):**
  ```ruby
  ctx[:user_exists] = User.where(email: "test@example.com").exists?
  true
  ```
- **Generated code (any):**
  ```ruby
  ctx[:has_orders] = Order.where(status: "pending", customer_id: ctx[:customer_id]).any?
  true
  ```
- **Generated code (none):**
  ```ruby
  ctx[:no_duplicates] = Invoice.where(reference: ctx[:ref]).none?
  true
  ```
- **Validation:** modelName and targetVariable required.

### 2.2 CountRecords

Counts records matching criteria.

- **Category:** `model_operations`
- **Config:** `modelName` (string), `conditions` (hash, optional), `conditionVariable` (string, optional), `targetVariable` (string), `distinct` (boolean, default false), `distinctField` (string, optional)
- **Generated code (simple):**
  ```ruby
  ctx[:order_count] = Order.where(status: "active").count
  true
  ```
- **Generated code (distinct):**
  ```ruby
  ctx[:unique_customers] = Order.where(status: "active").distinct.count(:customer_id)
  true
  ```
- **Validation:** modelName and targetVariable required.

### 2.3 PluckFields

Efficiently extracts column values without instantiating models.

- **Category:** `model_operations`
- **Config:** `modelName` (string), `fields` (array of strings), `conditions` (hash, optional), `conditionVariable` (string, optional), `targetVariable` (string), `uniq` (boolean, default false)
- **Generated code (single field):**
  ```ruby
  ctx[:emails] = User.where(active: true).pluck(:email)
  true
  ```
- **Generated code (multiple fields):**
  ```ruby
  ctx[:user_data] = User.where(role: "admin").pluck(:id, :name, :email)
  true
  ```
- **Generated code (with uniq):**
  ```ruby
  ctx[:categories] = Product.where(active: true).distinct.pluck(:category)
  true
  ```
- **Validation:** modelName, fields (non-empty array), and targetVariable required.

### 2.4 AggregateQuery

Database-level aggregation with optional GROUP BY.

- **Category:** `model_operations`
- **Config:** `modelName` (string), `aggregateFunction` (enum: `sum`, `average`, `minimum`, `maximum`, `count`), `aggregateField` (string), `groupByFields` (array of strings, optional), `conditions` (hash, optional), `conditionVariable` (string, optional), `targetVariable` (string), `having` (hash, optional)
- **Generated code (simple):**
  ```ruby
  ctx[:total_revenue] = Order.where(status: "completed").sum(:amount)
  true
  ```
- **Generated code (grouped):**
  ```ruby
  ctx[:revenue_by_category] = Product.where(active: true).group(:category).sum(:price)
  true
  ```
- **Generated code (grouped with having):**
  ```ruby
  ctx[:popular_categories] = Product.group(:category).having("COUNT(*) > 5").count
  true
  ```
- **Validation:** modelName, aggregateFunction, aggregateField, and targetVariable required.

---

## Part 3: New Step Actions — Data Operations (6)

Under `element_types/process/data_operations/`.

### 3.1 GroupCollection

Groups an in-memory array by a field.

- **Category:** `data_operations`
- **Config:** `sourceVariable` (string), `targetVariable` (string), `groupField` (string)
- **Generated code:**
  ```ruby
  ctx[:by_status] = ctx[:orders].group_by { |item| item[:status] }
  true
  ```
- **Output:** Hash where keys are grouped field values, values are arrays.
- **Validation:** sourceVariable and groupField required.

### 3.2 UniqCollection

Deduplicates an array, optionally by field.

- **Category:** `data_operations`
- **Config:** `sourceVariable` (string), `targetVariable` (string), `uniqField` (string, optional)
- **Generated code (by field):**
  ```ruby
  ctx[:unique_users] = ctx[:users].uniq { |item| item[:email] }
  true
  ```
- **Generated code (whole item):**
  ```ruby
  ctx[:unique_items] = ctx[:items].uniq
  true
  ```
- **Validation:** sourceVariable required.

### 3.3 MergeData

Deep or shallow merge of two hashes.

- **Category:** `data_operations`
- **Config:** `sourceVariable` (string — base hash), `mergeVariable` (string — hash to merge in), `targetVariable` (string), `strategy` (enum: `shallow`, `deep`; default `shallow`), `conflictResolution` (enum: `overwrite`, `keep_original`; default `overwrite`)
- **Generated code (shallow overwrite):**
  ```ruby
  ctx[:merged] = ctx[:defaults].merge(ctx[:overrides])
  true
  ```
- **Generated code (deep overwrite):**
  ```ruby
  ctx[:merged] = ctx[:defaults].deep_merge(ctx[:overrides])
  true
  ```
- **Generated code (shallow keep_original):**
  ```ruby
  ctx[:merged] = ctx[:overrides].merge(ctx[:defaults])
  true
  ```
- **Generated code (deep keep_original):**
  ```ruby
  ctx[:merged] = ctx[:overrides].deep_merge(ctx[:defaults])
  true
  ```
- **Validation:** sourceVariable and mergeVariable required.

### 3.4 SerializeData

Serializes structured data into a string format. Inverse of ParseData.

- **Category:** `data_operations`
- **Config:** `sourceVariable` (string), `targetVariable` (string), `format` (enum: `json`, `xml`, `yaml`, `csv`), `pretty` (boolean, default false), `csvColumns` (array of strings, optional), `rootElement` (string, optional — XML root, default `"data"`)
- **Generated code (JSON):**
  ```ruby
  ctx[:json_output] = ctx[:data].to_json
  true
  ```
- **Generated code (JSON pretty):**
  ```ruby
  ctx[:json_output] = JSON.pretty_generate(ctx[:data])
  true
  ```
- **Generated code (CSV):**
  ```ruby
  ctx[:csv_output] = CSV.generate do |csv|
    csv << ["name", "email"]
    ctx[:rows].each { |row| csv << [row[:name], row[:email]] }
  end
  true
  ```
- **Generated code (YAML):**
  ```ruby
  ctx[:yaml_output] = ctx[:data].to_yaml
  true
  ```
- **Generated code (XML):**
  ```ruby
  ctx[:xml_output] = ctx[:data].to_xml(root: "data")
  true
  ```
- **Validation:** sourceVariable required. format must be in allowed list.

### 3.5 DateTimeCalc

Date/time arithmetic, parsing, and formatting.

- **Category:** `data_operations`
- **Config:** `operation` (enum: `add`, `subtract`, `difference`, `format`, `parse`, `now`), `sourceVariable` (string, optional — not needed for `now`), `targetVariable` (string), `amount` (integer, optional), `unit` (enum: `seconds`, `minutes`, `hours`, `days`, `weeks`, `months`, `years`; optional), `formatString` (string, optional), `timezone` (string, optional)
- **Generated code (now):**
  ```ruby
  ctx[:current_time] = Time.current
  true
  ```
- **Generated code (add):**
  ```ruby
  ctx[:due_date] = ctx[:created_at] + 30.days
  true
  ```
- **Generated code (subtract):**
  ```ruby
  ctx[:start_date] = ctx[:end_date] - 2.weeks
  true
  ```
- **Generated code (difference):**
  ```ruby
  ctx[:days_elapsed] = (ctx[:end_date].to_date - ctx[:start_date].to_date).to_i
  true
  ```
- **Generated code (format):**
  ```ruby
  ctx[:formatted] = ctx[:timestamp].strftime("%B %d, %Y")
  true
  ```
- **Generated code (parse):**
  ```ruby
  ctx[:parsed_date] = Time.zone.parse(ctx[:date_string])
  true
  ```
- **Generated code (with timezone):**
  ```ruby
  ctx[:local_time] = ctx[:timestamp].in_time_zone("America/New_York")
  true
  ```
- **Validation:** targetVariable required. add/subtract require amount and unit. format requires formatString. parse requires sourceVariable.

### 3.6 RegexExtract

Matches a regex against a string and extracts matches or capture groups.

- **Category:** `data_operations`
- **Config:** `sourceVariable` (string), `targetVariable` (string), `pattern` (string), `operation` (enum: `match`, `scan`, `test`, `replace`; default `match`), `replacement` (string, optional), `captureGroup` (integer, optional)
- **Generated code (match):**
  ```ruby
  _match = ctx[:text].match(/(\d{3})-(\d{4})/)
  ctx[:phone_parts] = _match ? _match.captures : []
  true
  ```
- **Generated code (match with capture group):**
  ```ruby
  _match = ctx[:text].match(/Order #(\d+)/)
  ctx[:order_id] = _match ? _match[1] : nil
  true
  ```
- **Generated code (scan):**
  ```ruby
  ctx[:all_emails] = ctx[:text].scan(/[\w.+-]+@[\w-]+\.[\w.]+/)
  true
  ```
- **Generated code (test):**
  ```ruby
  ctx[:is_valid] = ctx[:input].match?(/\A\d{5}(-\d{4})?\z/)
  true
  ```
- **Generated code (replace):**
  ```ruby
  ctx[:cleaned] = ctx[:raw_text].gsub(/[^\w\s]/, "")
  true
  ```
- **Validation:** sourceVariable and pattern required. replace requires replacement.

---

## Part 4: New Step Actions — Security (3)

Under `element_types/process/security/`.

### 4.1 Authenticate

Verifies credentials, tokens, or API keys. Distinct from Authorize (permissions) — Authenticate checks identity.

- **Category:** `security`
- **Config:** `authMethod` (enum: `password`, `token`, `api_key`, `jwt`), `sourceVariable` (string), method-specific config:
  - `password`: `userVariable` (string)
  - `token`: `tokenType` (enum: `bearer`, `basic`, `custom`), `secretVariable` (string, optional)
  - `api_key`: `expectedKeyVariable` (string)
  - `jwt`: `secretVariable` (string), `algorithm` (string, default `"HS256"`)
- `targetVariable` (string), `failAction` (enum: `fail_track`, `raise`; default `fail_track`)
- **Generated code (password):**
  ```ruby
  ctx[:authenticated] = ctx[:user]&.authenticate(ctx[:password_input])
  unless ctx[:authenticated]
    Railway.fail!
  end
  true
  ```
- **Generated code (jwt):**
  ```ruby
  ctx[:jwt_payload] = JWT.decode(ctx[:token], ctx[:jwt_secret], true, algorithm: "HS256").first
  true
  rescue JWT::DecodeError => e
    Railway.fail!
  ```
- **Generated code (api_key):**
  ```ruby
  unless ActiveSupport::SecurityUtils.secure_compare(ctx[:provided_key].to_s, ctx[:valid_api_key].to_s)
    Railway.fail!
  end
  ctx[:api_authenticated] = true
  true
  ```
- **Validation:** authMethod and sourceVariable required. jwt requires secretVariable.

### 4.2 HashData

Produces irreversible hashes. Distinct from EncryptData (reversible).

- **Category:** `security`
- **Config:** `sourceVariable` (string), `targetVariable` (string), `algorithm` (enum: `sha256`, `sha512`, `md5`, `bcrypt`), `saltVariable` (string, optional), `cost` (integer, default 12 — bcrypt only)
- **Generated code (sha256):**
  ```ruby
  ctx[:hashed] = Digest::SHA256.hexdigest(ctx[:raw_value].to_s)
  true
  ```
- **Generated code (sha256 with salt):**
  ```ruby
  ctx[:hashed] = Digest::SHA256.hexdigest(ctx[:salt] + ctx[:raw_value].to_s)
  true
  ```
- **Generated code (bcrypt):**
  ```ruby
  ctx[:hashed_password] = BCrypt::Password.create(ctx[:password], cost: 12)
  true
  ```
- **Generated code (md5):**
  ```ruby
  ctx[:checksum] = Digest::MD5.hexdigest(ctx[:content].to_s)
  true
  ```
- **Validation:** sourceVariable required. algorithm must be in allowed list.

### 4.3 GenerateToken

Generates secure tokens — JWTs, random tokens, HMAC signatures.

- **Category:** `security`
- **Config:** `tokenType` (enum: `secure_random`, `jwt`, `hmac`, `uuid`), `targetVariable` (string), type-specific config:
  - `secure_random`: `length` (integer, default 32)
  - `jwt`: `payloadVariable` (string), `secretVariable` (string), `algorithm` (string, default `"HS256"`), `expiresIn` (integer seconds, optional)
  - `hmac`: `dataVariable` (string), `secretVariable` (string), `digest` (enum: `sha256`, `sha512`; default `sha256`)
  - `uuid`: (no extra config)
- **Generated code (secure_random):**
  ```ruby
  ctx[:api_token] = SecureRandom.hex(32)
  true
  ```
- **Generated code (jwt):**
  ```ruby
  _payload = ctx[:claims].merge(exp: Time.current.to_i + 3600)
  ctx[:jwt_token] = JWT.encode(_payload, ctx[:jwt_secret], "HS256")
  true
  ```
- **Generated code (hmac):**
  ```ruby
  ctx[:signature] = OpenSSL::HMAC.hexdigest("SHA256", ctx[:secret], ctx[:request_body])
  true
  ```
- **Generated code (uuid):**
  ```ruby
  ctx[:uuid] = SecureRandom.uuid
  true
  ```
- **Validation:** targetVariable required. jwt requires payloadVariable and secretVariable. hmac requires dataVariable and secretVariable.

---

## Part 5: New Step Actions — Concurrency & Service Invocation (2)

### 5.1 AcquireLock

Acquires a lock to prevent race conditions. New category: `concurrency`.

- **Category:** `concurrency`
- **Config:** `lockType` (enum: `advisory`, `pessimistic`, `redis`), type-specific config:
  - `advisory`: `lockKey` (string), `lockKeyVariable` (string, optional), `timeout` (integer seconds, default 5)
  - `pessimistic`: `modelVariable` (string), `reloadAfterLock` (boolean, default true)
  - `redis`: `lockKey` (string), `lockKeyVariable` (string, optional), `ttl` (integer seconds, default 30), `retryCount` (integer, default 3), `retryDelay` (float seconds, default 0.2)
- `targetVariable` (string, optional), `failAction` (enum: `fail_track`, `raise`; default `fail_track`)
- **Generated code (advisory):**
  ```ruby
  _lock_id = Zlib.crc32("order_processing_#{ctx[:order_id]}")
  _acquired = ActiveRecord::Base.connection.execute("SELECT pg_try_advisory_lock(#{_lock_id})").first["pg_try_advisory_lock"]
  unless _acquired
    Railway.fail!
  end
  ctx[:_advisory_lock_id] = _lock_id
  true
  ```
- **Generated code (pessimistic):**
  ```ruby
  ctx[:order] = ctx[:order].lock!
  ctx[:order].reload
  true
  ```
- **Generated code (redis):**
  ```ruby
  _lock_key = "lock:inventory_#{ctx[:product_id]}"
  _acquired = false
  3.times do
    _acquired = Redis.current.set(_lock_key, ctx[:_workflow_id], nx: true, ex: 30)
    break if _acquired
    sleep 0.2
  end
  unless _acquired
    Railway.fail!
  end
  ctx[:_redis_lock_key] = _lock_key
  true
  ```
- **Note:** Lock release is the developer's responsibility. Advisory locks release on connection close or explicit unlock, pessimistic locks release on transaction end, Redis locks expire via TTL.
- **Validation:** lockType required. advisory requires lockKey or lockKeyVariable. pessimistic requires modelVariable. redis requires lockKey or lockKeyVariable.

### 5.2 InvokeService

Calls a plain Ruby service object (PORO). New category: `service_invocation`. Bridges flowchart workflows and hand-written service classes.

- **Category:** `service_invocation`
- **Config:** `serviceClass` (string — fully qualified class name), `callMethod` (string, default `"call"`), `arguments` (array of `{ "name": "param_name", "sourceVariable": "ctx_var" }`, optional), `keywordArguments` (hash of `{ "param_name": "ctx_var" }`, optional), `targetVariable` (string)
- **Generated code (simple):**
  ```ruby
  ctx[:result] = PaymentProcessor.call
  true
  ```
- **Generated code (positional arguments):**
  ```ruby
  ctx[:receipt] = InvoiceGenerator.call(ctx[:order], ctx[:customer])
  true
  ```
- **Generated code (keyword arguments):**
  ```ruby
  ctx[:report] = ReportBuilder.call(start_date: ctx[:from_date], end_date: ctx[:to_date], format: ctx[:output_format])
  true
  ```
- **Generated code (custom method):**
  ```ruby
  ctx[:shipping_rate] = ShippingCalculator.new.estimate(ctx[:package], ctx[:destination])
  true
  ```
  When `callMethod` is not `"call"`, uses `.new.method()` pattern.
- **Validation:** serviceClass and targetVariable required.

---

## Part 6: Implementation Phases

### Phase 1: Model Operations & Data Operations (10 generators)
Most commonly needed. Zero dependencies on new infrastructure.

| # | Generator | Category |
|---|-----------|----------|
| 1 | CheckExistence | model_operations |
| 2 | CountRecords | model_operations |
| 3 | PluckFields | model_operations |
| 4 | AggregateQuery | model_operations |
| 5 | GroupCollection | data_operations |
| 6 | UniqCollection | data_operations |
| 7 | MergeData | data_operations |
| 8 | SerializeData | data_operations |
| 9 | DateTimeCalc | data_operations |
| 10 | RegexExtract | data_operations |

### Phase 2: Security, Concurrency, Service Invocation (5 generators)
Introduces 2 new category directories. Slightly more complex configs.

| # | Generator | Category |
|---|-----------|----------|
| 11 | Authenticate | security |
| 12 | HashData | security |
| 13 | GenerateToken | security |
| 14 | AcquireLock | concurrency (new) |
| 15 | InvokeService | service_invocation (new) |

### Phase 3: Simple Structural Elements (2 generators)
Follow patterns established by Decision and Loop.

| # | Generator | Type |
|---|-----------|------|
| 16 | Switch | element_type |
| 17 | Transaction | element_type |

### Phase 4: Complex Structural Elements (3 generators)
Require sophisticated code generation and supporting infrastructure.

| # | Generator | Type |
|---|-----------|------|
| 18 | Saga | element_type |
| 19 | SignalWait | element_type |
| 20 | ParallelForEach | element_type |

**Rationale:** Phase 1 delivers most value fastest. Phase 2 adds specialized step actions. Phase 3 adds structural elements mirroring existing patterns. Phase 4 tackles the most complex generators last.

Each phase is independently usable — no cross-phase dependencies.

---

## Part 7: File Structure & Testing

### New Files (40 total: 20 generators + 20 specs)

**Structural Elements:**
```
app/services/code_generators/element_types/switch/switch_generator.rb
app/services/code_generators/element_types/transaction/transaction_generator.rb
app/services/code_generators/element_types/saga/saga_generator.rb
app/services/code_generators/element_types/signal_wait/signal_wait_generator.rb
app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb
spec/services/code_generators/element_types/switch/switch_generator_spec.rb
spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb
spec/services/code_generators/element_types/saga/saga_generator_spec.rb
spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb
spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb
```

**Step Actions:**
```
app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb
app/services/code_generators/element_types/process/model_operations/count_records_generator.rb
app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb
app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb
app/services/code_generators/element_types/process/data_operations/group_collection_generator.rb
app/services/code_generators/element_types/process/data_operations/uniq_collection_generator.rb
app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb
app/services/code_generators/element_types/process/data_operations/serialize_data_generator.rb
app/services/code_generators/element_types/process/data_operations/date_time_calc_generator.rb
app/services/code_generators/element_types/process/data_operations/regex_extract_generator.rb
app/services/code_generators/element_types/process/security/authenticate_generator.rb
app/services/code_generators/element_types/process/security/hash_data_generator.rb
app/services/code_generators/element_types/process/security/generate_token_generator.rb
app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb
app/services/code_generators/element_types/process/service_invocation/invoke_service_generator.rb
spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb
spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb
spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb
spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb
spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb
spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb
spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb
spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb
spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb
spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb
spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb
spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb
spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb
spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb
spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb
```

### Testing Pattern

Every spec follows the established convention:
```ruby
RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::GroupCollectionGenerator do
  it_behaves_like "a code generator"

  describe "#generate" do
    # Test each config variant
    # Test generated code is valid Ruby (syntax check)
    # Test output variable assignment
  end

  describe "#validate_config" do
    # Test required fields produce errors when missing
    # Test invalid enum values produce errors
    # Test valid config returns empty errors array
  end

  describe "#example_output" do
    it "returns a non-empty string" do
      expect(subject.example_output).to be_a(String)
      expect(subject.example_output).not_to be_empty
    end
  end
end
```

### Changes to Existing Files

Only one modification to an existing file:
- **SourceAssembler::CATEGORIES** — add `:concurrency` and `:service_invocation` to the CATEGORIES array

Everything else is auto-discovered by `GeneratorRegistry` via filesystem scan.
