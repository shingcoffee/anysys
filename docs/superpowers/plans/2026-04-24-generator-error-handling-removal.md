# Generator Error Handling Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all error-raising behavior from code generators so generated Trailblazer Activity code fails gracefully via `return false` (fail_track), with error handling centralized in `dynamic_controller.rb`.

**Architecture:** Each generator that currently raises exceptions or supports "raise" error strategies will be modified to instead return `false` or `nil`. JS action config schemas will have "raise"/"error" options removed from their enums. After JS changes, `rake config_schemas:mirror` regenerates the Ruby mirror.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, JavaScript (ES6 modules), Trailblazer Activity

---

## File Structure

**Ruby generators to modify (15 files):**
- `app/services/code_generators/element_types/process/validation/validate_contract_generator.rb`
- `app/services/code_generators/element_types/process/validation/build_contract_generator.rb`
- `app/services/code_generators/element_types/process/caching/cache_read_generator.rb`
- `app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb`
- `app/services/code_generators/element_types/process/caching/cache_delete_generator.rb`
- `app/services/code_generators/element_types/process/background/enqueue_job_generator.rb`
- `app/services/code_generators/element_types/process/background/schedule_job_generator.rb`
- `app/services/code_generators/element_types/process/communication/send_email_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/calculate_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb`
- `app/services/code_generators/element_types/process/file_operations/compress_files_generator.rb`
- `app/services/code_generators/element_types/process/file_operations/parse_csv_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/bulk_import_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/destroy_model_generator.rb`
- `app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb`

**JS schema files to modify (4 files):**
- `app/javascript/flowchart/constants/action_configs/validation_actions.js`
- `app/javascript/flowchart/constants/action_configs/caching_actions.js`
- `app/javascript/flowchart/constants/action_configs/data_actions.js`
- `app/javascript/flowchart/constants/action_configs/model_actions.js`

**Test files to update (matching each generator):**
- Corresponding specs under `spec/services/code_generators/`

---

### Task 1: validate_contract_generator.rb — Remove raise options

**Files:**
- Modify: `app/services/code_generators/element_types/process/validation/validate_contract_generator.rb`
- Test: `spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb`

- [ ] **Step 1: Update ON_FAILURES constant**

Remove "raise" from the allowed values:

```ruby
ON_FAILURES       = %w[fail_track collect_errors].freeze
```

- [ ] **Step 2: Update on_failure_handler method**

Remove the "raise" case from the method at lines 121-129. The method should become:

```ruby
def on_failure_handler(on_failure, error_var)
  case on_failure
  when "collect_errors"
    "# collect_errors: continue even on invalid; errors available at ctx[:#{error_var}]"
  else # fail_track
    "return false unless _valid"
  end
end
```

- [ ] **Step 3: Update permission_check_line to return false instead of raise**

Change lines 102-114 to use `return false` instead of `raise`:

```ruby
def permission_check_line(permission_check)
  case permission_check
  when "policy"
    policy_action = config["policyAction"] || "update?"
    user_expression = config["userExpression"] || "ctx[:current_user]"
    record_expression = config["recordExpression"] || "ctx[:model]"
    "return false unless Pundit.policy(#{user_expression}, #{record_expression}).#{policy_action}"
  when "explicit"
    expression = config["permissionExpression"] || "ctx[:permission_granted]"
    "return false unless #{expression}"
  else
    "# permission check: none"
  end
end
```

- [ ] **Step 4: Update strict_mode_check to return false instead of raise**

Change lines 94-99 to use `return false`:

```ruby
def strict_mode_check(contract_ref)
  <<~RUBY.chomp
    _known_keys = _contract.respond_to?(:schema) ? _contract.schema.key_map.map(&:name).map(&:to_s) : _contract.class.properties.map(&:to_s)
    _unknown_keys = entity_params.keys.map(&:to_s) - _known_keys
    return false unless _unknown_keys.empty?
  RUBY
end
```

- [ ] **Step 5: Update generate_permission_check for role_check and policy_check**

Change lines 149-180 to use `return false` instead of `raise`:

```ruby
def generate_permission_check
  permission_type = config["permissionType"]

  case permission_type
  when "role_check"
    role_expression = config["roleExpression"] || "ctx[:current_user].role"
    required_role = config["requiredRole"] || "admin"
    <<~RUBY.chomp
      return false unless #{role_expression} == "#{required_role}"
      true
    RUBY
  when "policy_check"
    policy_class = config["policyClass"] || "ApplicationPolicy"
    policy_action = config["policyAction"] || "show?"
    user_expression = config["userExpression"] || "ctx[:current_user]"
    record_expression = config["recordExpression"] || "ctx[:model]"
    <<~RUBY.chomp
      if defined?(Pundit)
        return false unless Pundit.policy(#{user_expression}, #{record_expression}).#{policy_action}
      elsif defined?(#{policy_class})
        return false unless #{policy_class}.new(#{user_expression}, #{record_expression}).#{policy_action}
      else
        return false
      end
      true
    RUBY
  else
    <<~RUBY.chomp
      # Permission check: no permission type configured
      ctx[:result] = true
    RUBY
  end
end
```

- [ ] **Step 6: Update validate_config to remove onFailure validation for "raise"**

The ON_FAILURES constant change handles this automatically.

- [ ] **Step 7: Run tests to verify changes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb -v`
Expected: All tests pass (some may need updating if they expect "raise" behavior)

- [ ] **Step 8: Update any failing tests**

Update test expectations that check for "raise" behavior to expect "return false" instead.

- [ ] **Step 9: Commit**

```bash
git add app/services/code_generators/element_types/process/validation/validate_contract_generator.rb spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(validate_contract): remove raise options, use return false

Error handling is centralized in dynamic_controller.rb.
- Remove "raise" from ON_FAILURES enum
- Permission checks now return false instead of raising
- Strict mode returns false on unknown attributes

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: build_contract_generator.rb — Remove class existence raise

**Files:**
- Modify: `app/services/code_generators/element_types/process/validation/build_contract_generator.rb`
- Test: `spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb`

- [ ] **Step 1: Update build_simple_build_code method**

Change lines 145-152 to trust the class loader (remove the raise):

```ruby
def build_simple_build_code(contract_class, target)
  <<~RUBY.chomp
    ctx[:#{target}] = #{contract_class}.build_for(ctx[:bound_entity]).new(ctx[:model], _contract_attrs)
  RUBY
end
```

- [ ] **Step 2: Update build_cache_contract_code method**

Change lines 166-192 to remove the raise in the non-cached branch. The method builds the contract inside a memoization block. Update the else branch:

```ruby
def build_cache_contract_code(contract_class, target, cache_per_class)
  build_line = if cache_per_class
                 <<~BUILD.chomp
                   _entity = ctx[:bound_entity]
                   _cache_key = "contract_build:#{contract_class}:\#{_entity.respond_to?(:name) ? _entity.name : _entity.class.name}"
                   _builder = Rails.cache.fetch(_cache_key, expires_in: 1.hour) do
                     #{contract_class}.build_for(_entity)
                   end
                   ctx[:_contract_#{target}] = _builder.new(ctx[:model], _contract_attrs)
                 BUILD
               else
                 <<~BUILD.chomp
                   ctx[:_contract_#{target}] = #{contract_class}.build_for(ctx[:bound_entity]).new(ctx[:model], _contract_attrs)
                 BUILD
               end

  <<~RUBY.chomp
    ctx[:#{target}] = ctx[:_contract_#{target}] ||= begin
      #{build_line.lines.map.with_index { |l, i| i.zero? ? l.chomp : "  #{l.chomp}" }.join("\n")}
      ctx[:_contract_#{target}]
    end
  RUBY
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb -v`

- [ ] **Step 4: Update any failing tests**

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/validation/build_contract_generator.rb spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(build_contract): remove class existence checks

Trust class loader to handle undefined contract classes.
Controller catches any runtime NameError.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: cache_read_generator.rb — Remove raise on miss

**Files:**
- Modify: `app/services/code_generators/element_types/process/caching/cache_read_generator.rb`
- Test: `spec/services/code_generators/element_types/process/caching/cache_read_generator_spec.rb`

- [ ] **Step 1: Update ON_MISS_BEHAVIOR constant**

Remove "raise" from the allowed values at line 10:

```ruby
ON_MISS_BEHAVIOR = %w[nil default].freeze
```

- [ ] **Step 2: Update append_miss_handler method**

Remove the "raise" case from lines 87-96:

```ruby
def append_miss_handler(code, target, on_miss, default_v)
  case on_miss
  when "default"
    literal = default_v.empty? ? "nil" : default_v
    "#{code}\nctx[:#{target}] ||= #{literal}\ntrue"
  else # nil
    "#{code}\ntrue"
  end
end
```

- [ ] **Step 3: Update validate_config**

The ON_MISS_BEHAVIOR constant change handles validation automatically.

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/caching/cache_read_generator_spec.rb -v`

- [ ] **Step 5: Update any failing tests**

- [ ] **Step 6: Commit**

```bash
git add app/services/code_generators/element_types/process/caching/cache_read_generator.rb spec/services/code_generators/element_types/process/caching/cache_read_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(cache_read): remove raise on cache miss

Cache misses now return nil (default behavior).

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: cache_fetch_generator.rb — Remove raise fallback strategy

**Files:**
- Modify: `app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb`
- Test: `spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb`

- [ ] **Step 1: Update FALLBACK_ERROR_STRATEGIES constant**

Remove "raise" from line 11:

```ruby
FALLBACK_ERROR_STRATEGIES = %w[nil default].freeze
```

- [ ] **Step 2: Update wrap_fallback_with_strategy method**

The method at lines 79-92 wraps fallback in error handling. Update to always wrap (no "raise" passthrough):

```ruby
def wrap_fallback_with_strategy(fallback_code)
  strategy = config["fallbackErrorStrategy"]
  
  on_rescue = case strategy
              when "default" then "ctx[:#{config['resultVar'] || 'result'}]"
              else "nil"  # nil or unset
              end

  "begin; #{fallback_code}; rescue => _fallback_error; #{on_rescue}; end"
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb -v`

- [ ] **Step 4: Update any failing tests**

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(cache_fetch): remove raise fallback error strategy

Fallback errors now return nil or default value.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: cache_delete_generator.rb — Remove raise on large pattern

**Files:**
- Modify: `app/services/code_generators/element_types/process/caching/cache_delete_generator.rb`
- Test: `spec/services/code_generators/element_types/process/caching/cache_delete_generator_spec.rb`

- [ ] **Step 1: Update build_pattern_delete method**

Change lines 86-109 to skip silently instead of raising when pattern matches too many keys:

```ruby
def build_pattern_delete(key, confirm)
  if confirm
    <<~RUBY.chomp
      if Rails.cache.respond_to?(:delete_matched)
        matched = if Rails.cache.respond_to?(:instance_variable_get) && Rails.cache.instance_variable_get(:@data).respond_to?(:keys)
          Rails.cache.instance_variable_get(:@data).keys.grep(Regexp.new(#{key.inspect}))
        else
          []
        end
        unless matched.size >= #{MAX_PATTERN_KEYS}
          Rails.cache.delete_matched(#{key.inspect})
        end
      end
      true
    RUBY
  else
    <<~RUBY.chomp
      if Rails.cache.respond_to?(:delete_matched)
        Rails.cache.delete_matched(#{key.inspect})
      end
      true
    RUBY
  end
end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/caching/cache_delete_generator_spec.rb -v`

- [ ] **Step 3: Update any failing tests**

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/element_types/process/caching/cache_delete_generator.rb spec/services/code_generators/element_types/process/caching/cache_delete_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(cache_delete): skip silently on large pattern match

Instead of raising when pattern matches >= 10k keys, just skip the delete.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: enqueue_job_generator.rb — Remove class existence raise

**Files:**
- Modify: `app/services/code_generators/element_types/process/background/enqueue_job_generator.rb`
- Test: `spec/services/code_generators/element_types/process/background/enqueue_job_generator_spec.rb`

- [ ] **Step 1: Update generate_body method**

Remove the `defined?` checks and `raise NameError` from lines 39-63. Just call the job directly:

```ruby
def generate_body
  job_class = config["jobClass"] || "ApplicationJob"
  job_args = config["jobArgs"]
  queue = fetch_with_default("queueName", "default")
  priority = config["priority"]
  perform_mode = fetch_enum("performMode", PERFORM_MODES, default: "later")
  adapter = fetch_enum("adapter", ADAPTERS, default: "active_job")
  wait_until = config["waitUntil"].to_s.strip
  job_id = config["jobId"].to_s.strip
  retry_set = config["retrySet"]
  discard_on = kv_rows(config["discardOn"]).map { |r| r[:key] }.reject(&:empty?)
  retry_on   = kv_rows(config["retryOn"]).map { |r| r[:key] }.reject(&:empty?)

  args_part = job_args.present? ? "(#{condition_operand_to_ruby(job_args)})" : ""

  inner = if perform_mode == "now"
            "#{job_class}.perform_now#{args_part}"
          else
            set_opts = ["queue: \"#{queue}\""]
            set_opts << "priority: #{priority}" if priority.present?
            set_opts << "wait_until: #{wait_until}" if wait_until.present?
            perform_chain = "#{job_class}.set(#{set_opts.join(", ")}).perform_later#{args_part}"
            if job_id.present?
              perform_chain = "#{job_class}.set(#{set_opts.join(", ")}).enqueue(job_id: #{job_id.inspect})" \
                ".tap { |_| #{job_class}.set(#{set_opts.join(", ")}).perform_later#{args_part} }"
            end
            perform_chain
          end

  comment_lines = []
  comment_lines << "# Adapter: #{adapter}"
  comment_lines << "# Retry attempts: #{retry_set}" if retry_set.present?
  comment_lines << "# discard_on: #{discard_on.join(', ')}" if discard_on.any?
  comment_lines << "# retry_on: #{retry_on.join(', ')}"     if retry_on.any?
  annotated = ([*comment_lines, inner]).join("\n")

  "#{annotated}\ntrue"
end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/background/enqueue_job_generator_spec.rb -v`

- [ ] **Step 3: Update any failing tests**

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/element_types/process/background/enqueue_job_generator.rb spec/services/code_generators/element_types/process/background/enqueue_job_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(enqueue_job): remove class existence checks

Trust class loader; controller catches runtime NameError.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: schedule_job_generator.rb — Remove class existence and cron validation raises

**Files:**
- Modify: `app/services/code_generators/element_types/process/background/schedule_job_generator.rb`
- Test: `spec/services/code_generators/element_types/process/background/schedule_job_generator_spec.rb`

- [ ] **Step 1: Update emit_cron method**

Remove `raise NameError` and `raise ArgumentError` from lines 117-157. The cron parsing should fail gracefully:

```ruby
def emit_cron(job_class, args_part, scheduler, timezone)
  cron_expr = config["cronExpression"] || "0 * * * *"
  unique_for = config["uniqueFor"].to_i

  sidekiq_cron_emit = <<~RUBY.chomp
    if defined?(Sidekiq::Cron::Job)
      Sidekiq::Cron::Job.create(name: "#{job_class}-cron", cron: _cron, class: "#{job_class}")
    else
      #{job_class}.set(wait_until: _next).perform_later#{args_part}
    end
  RUBY

  default_emit = "#{job_class}.set(wait_until: _next).perform_later#{args_part}"

  body = scheduler == "sidekiq_cron" ? sidekiq_cron_emit : default_emit

  <<~RUBY.chomp
    _cron = #{cron_expr.to_s.inspect}
    _tz   = #{timezone.to_s.inspect}
    _unique_for = #{unique_for}
    if defined?(Fugit::Cron)
      _parsed = Fugit::Cron.parse(_cron)
      _next = _parsed ? _parsed.next_time.to_t : 1.hour.from_now
    else
      _next = 1.hour.from_now
    end
    #{body}
  RUBY
end
```

- [ ] **Step 2: Update emit_interval method**

Remove `raise NameError` from lines 159-186:

```ruby
def emit_interval(job_class, args_part)
  interval = fetch_int_positive("intervalSeconds", default: 60)
  limit    = config["recurrenceLimit"].to_i

  limit_clause = if limit > 0
                   "_max = #{limit}\n_iter = 0\n"
                 else
                   "_max = nil\n"
                 end

  loop_cond = limit > 0 ? "while _iter < _max" : "loop do"
  loop_end  = "end"
  increment = limit > 0 ? "\n  _iter += 1" : ""
  loop_open = limit > 0 ? "#{loop_cond}" : "loop do"

  <<~RUBY.chomp
    # background-note: interval scheduling should run inside a worker process
    #{limit_clause.chomp}
    #{loop_open}
      #{job_class}.perform_later#{args_part}
      sleep(#{interval})#{increment}
    #{loop_end}
  RUBY
end
```

- [ ] **Step 3: Update emit_at_time method**

Remove `raise NameError` from lines 188-210:

```ruby
def emit_at_time(job_class, args_part)
  run_at = config["runAt"] || config["scheduledAt"] || "1.hour.from_now"

  if resolve_schedule_type == "legacy_duration"
    value = fetch_int_positive("delayValue", default: 30)
    unit  = fetch_enum("delayUnit", DELAY_UNITS, default: "minutes")
    return "#{job_class}.set(wait: #{value}.#{unit}).perform_later#{args_part}"
  end

  "#{job_class}.set(wait_until: #{run_at}).perform_later#{args_part}"
end
```

- [ ] **Step 4: Update emit_recurring method**

Remove `raise NameError` from lines 213-240:

```ruby
def emit_recurring(job_class, args_part)
  limit    = config["recurrenceLimit"].to_i
  interval = fetch_int_positive("intervalSeconds", default: 3600)

  if limit > 0
    <<~RUBY.chomp
      # recurring: up to #{limit} iteration(s)
      _max = #{limit}
      _iter = 0
      while _iter < _max
        #{job_class}.set(wait: (_iter * #{interval}).seconds).perform_later#{args_part}
        _iter += 1
      end
    RUBY
  else
    <<~RUBY.chomp
      # recurring: unbounded; relies on scheduler re-enqueue
      #{job_class}.set(wait: #{interval}.seconds).perform_later#{args_part}
    RUBY
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/background/schedule_job_generator_spec.rb -v`

- [ ] **Step 6: Update any failing tests**

- [ ] **Step 7: Commit**

```bash
git add app/services/code_generators/element_types/process/background/schedule_job_generator.rb spec/services/code_generators/element_types/process/background/schedule_job_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(schedule_job): remove class existence and cron validation raises

Trust class loader; invalid cron falls back to 1.hour.from_now.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: send_email_generator.rb — Remove ERROR_STRATEGIES constant

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/send_email_generator.rb`
- Test: `spec/services/code_generators/element_types/process/communication/send_email_generator_spec.rb`

- [ ] **Step 1: Remove ERROR_STRATEGIES constant**

Delete line 11:

```ruby
ERROR_STRATEGIES = %w[continue fail_track raise].freeze
```

This constant is defined but never used in the generator (confirmed by reading the code).

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/communication/send_email_generator_spec.rb -v`

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/process/communication/send_email_generator.rb
git commit -m "$(cat <<'EOF'
refactor(send_email): remove unused ERROR_STRATEGIES constant

The constant was defined but never used.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: calculate_generator.rb — Remove error empty behavior

**Files:**
- Modify: `app/services/code_generators/element_types/process/data_operations/calculate_generator.rb`
- Test: `spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb`

- [ ] **Step 1: Update EMPTY_BEHAVIORS constant**

Remove "error" from line 10:

```ruby
EMPTY_BEHAVIORS = %w[zero nil].freeze
```

- [ ] **Step 2: Update generate_body method**

Change lines 40-48 to remove the "error" case:

```ruby
empty_value = if !empty_default_cfg.nil? && empty_default_cfg.to_s != ""
                empty_default_cfg.to_s
              else
                case empty_behavior
                when "nil" then "nil"
                else            "0"  # zero is default
                end
              end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb -v`

- [ ] **Step 4: Update any failing tests**

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/calculate_generator.rb spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(calculate): remove error option from emptyCollectionBehavior

Empty collections now return zero (default) or nil.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: merge_data_generator.rb — Remove error conflict option

**Files:**
- Modify: `app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb`
- Test: `spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb`

- [ ] **Step 1: Update ON_CONFLICT constant**

Remove "error" from line 10:

```ruby
ON_CONFLICT = %w[first last].freeze
```

- [ ] **Step 2: Update build_shallow_merge_body method**

Remove the "error" case from lines 127-140:

```ruby
def build_shallow_merge_body(target, left_expr, right_expr, on_conflict)
  case on_conflict
  when "first"
    "ctx[:#{target}] = #{right_expr}.merge(#{left_expr})\ntrue"
  else # "last"
    "ctx[:#{target}] = #{left_expr}.merge(#{right_expr})\ntrue"
  end
end
```

- [ ] **Step 3: Update build_deep_merge_body method**

Remove the "error" case from lines 167-198:

```ruby
def build_deep_merge_body(target, left_expr, right_expr, array_mode, on_conflict)
  array_combiner = array_combiner_expr(array_mode)
  scalar_combiner = scalar_combiner_expr(on_conflict)
  left_side, right_side = (on_conflict == "first") ? [right_expr, left_expr] : [left_expr, right_expr]

  <<~RUBY.chomp
    ctx[:#{target}] = #{left_side}.deep_merge(#{right_side}) do |_key, _l, _r|
      if _l.is_a?(Array) && _r.is_a?(Array)
        #{array_combiner}
      else
        #{scalar_combiner}
      end
    end
    true
  RUBY
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb -v`

- [ ] **Step 5: Update any failing tests**

- [ ] **Step 6: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(merge_data): remove error option from onConflict

Duplicate keys now use first or last (overwrite) strategy.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: compress_files_generator.rb — Remove ERROR_STRATEGIES constant

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/compress_files_generator.rb`
- Test: `spec/services/code_generators/element_types/process/file_operations/compress_files_generator_spec.rb`

- [ ] **Step 1: Remove ERROR_STRATEGIES constant**

Delete line 8:

```ruby
ERROR_STRATEGIES = %w[continue fail_track raise].freeze
```

This constant is defined but never used (confirmed by reading the code).

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/file_operations/compress_files_generator_spec.rb -v`

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/process/file_operations/compress_files_generator.rb
git commit -m "$(cat <<'EOF'
refactor(compress_files): remove unused ERROR_STRATEGIES constant

The constant was defined but never used.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: parse_csv_generator.rb — Remove ERROR_STRATEGIES constant

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/parse_csv_generator.rb`
- Test: `spec/services/code_generators/element_types/process/file_operations/parse_csv_generator_spec.rb`

- [ ] **Step 1: Remove ERROR_STRATEGIES constant**

Delete line 8:

```ruby
ERROR_STRATEGIES = %w[continue fail_track raise].freeze
```

This constant is defined but never used.

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/file_operations/parse_csv_generator_spec.rb -v`

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/process/file_operations/parse_csv_generator.rb
git commit -m "$(cat <<'EOF'
refactor(parse_csv): remove unused ERROR_STRATEGIES constant

The constant was defined but never used.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: bulk_import_generator.rb — Remove raise from onDuplicateKey

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/bulk_import_generator.rb`
- Test: `spec/services/code_generators/element_types/process/model_operations/bulk_import_generator_spec.rb`

- [ ] **Step 1: Update ON_DUPLICATE_KEY constant**

Remove "raise" from line 8:

```ruby
ON_DUPLICATE_KEY = %w[update skip].freeze
```

- [ ] **Step 2: Update build_import_code method**

Remove the "raise" case from lines 108-118:

```ruby
def build_import_code(data_key:, on_dup:, batch_size:, target:, unique_by:,
                      returning:, record_timestamps:, validate_records:, skip_duplicates:)
  case on_dup
  when "update"
    build_upsert(data_key, batch_size, target, unique_by, returning, record_timestamps, validate_records)
  else
    # "skip": use insert_all (skip duplicates) when skipDuplicates=true, otherwise insert_all
    build_insert(data_key, batch_size, target, returning, record_timestamps, validate_records, raise_on_error: false)
  end
end
```

- [ ] **Step 3: Update build_insert method**

Always use `insert_all` (non-raising). Update lines 145-166:

```ruby
def build_insert(data_key, batch_size, target, returning, record_timestamps, validate_records, raise_on_error:)
  returning_list = returning.map(&:to_sym).inspect
  opts = [
    "record_timestamps: #{record_timestamps}",
    "validate: #{validate_records}"
  ]
  opts << "returning: #{returning_list}" if returning.any?
  <<~RUBY.chomp
    _model_class = EntityEntry.build_for(ctx[:bound_entity])
    _total = 0
    _returned = []
    ctx[:#{data_key}].each_slice(#{batch_size}) do |batch|
      _rows = batch.map { |row| row.merge(customer_id: ctx[:customer_id]) }
      _result = _model_class.insert_all(_rows, #{opts.join(', ')})
      _returned.concat(_result.rows) if _result.respond_to?(:rows) && _result.rows
      _total += batch.size
    end
    ctx[:#{target}] = { imported_count: _total, returning: _returned }
    true
  RUBY
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/bulk_import_generator_spec.rb -v`

- [ ] **Step 5: Update any failing tests**

- [ ] **Step 6: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/bulk_import_generator.rb spec/services/code_generators/element_types/process/model_operations/bulk_import_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(bulk_import): remove raise from onDuplicateKey

Duplicates are now skipped (insert_all) or updated (upsert_all).

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: destroy_model_generator.rb — Replace raise with return false

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/destroy_model_generator.rb`
- Test: `spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb`

- [ ] **Step 1: Update prepend_password_guard method**

Change lines 86-89 to use `return false` instead of `raise`:

```ruby
def prepend_password_guard(code, confirm_expr, password_ctx_expr)
  return code if confirm_expr.empty?

  "return false unless #{password_ctx_expr} == #{confirm_expr}\n#{code}"
end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb -v`

- [ ] **Step 3: Update any failing tests**

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/destroy_model_generator.rb spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(destroy_model): use return false for password mismatch

Password confirmation failures now route to fail_track.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: parallel_for_each_generator.rb — Remove errorAggregation first_error raise

**Files:**
- Modify: `app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb`
- Test: `spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb`

- [ ] **Step 1: Update ERROR_AGGREGATIONS constant**

Remove "first_error" from line 7:

```ruby
ERROR_AGGREGATIONS = %w[all_errors none].freeze
```

- [ ] **Step 2: Update per_iteration_rescue method**

Remove the "first_error" case from lines 151-159:

```ruby
def per_iteration_rescue(error_agg)
  case error_agg
  when "all_errors"
    "ctx[:_thread_errors] << { message: thread_err.message, class: thread_err.class.name }"
  else # "none"
    "# errorAggregation=none; swallow per-iteration error"
  end
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb -v`

- [ ] **Step 4: Update any failing tests**

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor(parallel_for_each): remove first_error aggregation mode

Iteration errors are now collected (all_errors) or swallowed (none).

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: validation_actions.js — Remove error-related config options

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/validation_actions.js`

- [ ] **Step 1: Remove onFailure field from main configSchema (lines 126-130)**

Delete the `onFailure` field entry:

```javascript
{
  key: "onFailure",
  type: "text",
  label: "On Failure",
  placeholder: "raise | fail_track | collect_errors"
},
```

- [ ] **Step 2: Remove includeWarnings field from main configSchema (lines 131-135)**

Delete the `includeWarnings` field entry.

- [ ] **Step 3: Remove strictMode field from main configSchema (lines 136-140)**

Delete the `strictMode` field entry.

- [ ] **Step 4: Remove errorVar field from main configSchema (lines 141-145)**

Delete the `errorVar` field entry.

- [ ] **Step 5: Update configSchemaBySubOption.contract — remove onFailure**

In the `contract` sub-option (lines 228-238), update onFailure to remove "raise" option:

```javascript
{
  key: "onFailure",
  type: "select",
  label: "On Failure",
  defaultValue: "fail_track",
  options: [
    { value: "fail_track", label: "fail_track" },
    { value: "collect_errors", label: "collect_errors" }
  ]
},
```

- [ ] **Step 6: Remove includeWarnings from configSchemaBySubOption.contract (lines 239-248)**

Delete this field entry.

- [ ] **Step 7: Remove errorVar from configSchemaBySubOption.contract (lines 249-254)**

Delete this field entry.

- [ ] **Step 8: Remove strictMode from configSchemaBySubOption.contract (lines 255-264)**

Delete this field entry.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/flowchart/constants/action_configs/validation_actions.js
git commit -m "$(cat <<'EOF'
refactor(validation_actions.js): remove error handling config options

Remove onFailure raise option, includeWarnings, strictMode, errorVar.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: caching_actions.js — Remove error-related config options

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/caching_actions.js`

- [ ] **Step 1: Update cache_read onMiss options**

In the `cache_read` action (lines 64-73), remove "raise" from onMiss options:

```javascript
{
  key: "onMiss",
  type: "select",
  label: "On Miss",
  default: "nil",
  options: [
    { value: "nil", label: "nil" },
    { value: "default", label: "default" }
  ]
},
```

- [ ] **Step 2: Remove fallbackErrorStrategy from cache_fetch**

In the `cache_fetch` action (lines 283-294), remove the `fallbackErrorStrategy` field entirely.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/action_configs/caching_actions.js
git commit -m "$(cat <<'EOF'
refactor(caching_actions.js): remove error handling config options

Remove raise from onMiss, remove fallbackErrorStrategy field.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: data_actions.js — Remove error-related config options

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/data_actions.js`

- [ ] **Step 1: Update calculate emptyCollectionBehavior options**

In the `calculate` action (lines 314-322), remove "error" option:

```javascript
{
  key: "emptyCollectionBehavior",
  type: "select",
  label: "Empty Collection Behavior",
  default: "zero",
  options: [
    { value: "zero", label: "zero" },
    { value: "nil", label: "nil" }
  ]
},
```

- [ ] **Step 2: Update merge_data onConflict options**

In the `merge_data` action (lines 600-609), remove "error" option:

```javascript
{
  key: "onConflict",
  type: "select",
  label: "On Conflict",
  default: "last",
  options: [
    { value: "first", label: "first" },
    { value: "last", label: "last" }
  ]
},
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/action_configs/data_actions.js
git commit -m "$(cat <<'EOF'
refactor(data_actions.js): remove error options from enums

Remove error from emptyCollectionBehavior and onConflict.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: model_actions.js — Remove raise from onDuplicateKey

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/model_actions.js`

- [ ] **Step 1: Update bulk_import onDuplicateKey options**

In the `bulk_import` action (lines 1130-1140), remove "raise" option:

```javascript
{
  key: "onDuplicateKey",
  type: "select",
  label: "On Duplicate Key",
  default: "skip",
  options: [
    { value: "skip", label: "skip (insert_all)" },
    { value: "update", label: "update (upsert_all)" }
  ]
},
```

- [ ] **Step 2: Update upsert_model onConflict options**

In the `upsert_model` action (lines 591-600), remove "raise" option:

```javascript
{
  key: "onConflict",
  type: "select",
  label: "On Conflict",
  default: "update",
  options: [
    { value: "update", label: "update" },
    { value: "skip", label: "skip" }
  ]
},
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/action_configs/model_actions.js
git commit -m "$(cat <<'EOF'
refactor(model_actions.js): remove raise from duplicate key options

Remove raise from bulk_import onDuplicateKey and upsert_model onConflict.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: Regenerate Ruby schema mirror

**Files:**
- Generated: `app/services/code_generators/config_schemas.rb` (or wherever mirror lives)

- [ ] **Step 1: Run rake task**

Run: `bundle exec rake config_schemas:mirror`
Expected: Task completes successfully, mirror file updated

- [ ] **Step 2: Verify no diff errors**

Run: `git diff app/services/code_generators/`
Expected: Only the expected enum changes appear in the mirror

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/
git commit -m "$(cat <<'EOF'
chore: regenerate Ruby config schema mirror

Run rake config_schemas:mirror after JS schema updates.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 21: Run full test suite and audit

- [ ] **Step 1: Run full generator test suite**

Run: `bundle exec rspec spec/services/code_generators/ --format progress`
Expected: All tests pass

- [ ] **Step 2: Run generator-UI audit script**

Run: `ruby scripts/audit_generator_ui.rb`
Expected: No mismatches between generator config keys and UI schemas

- [ ] **Step 3: Fix any remaining test failures**

Address any tests that still expect raise behavior.

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "$(cat <<'EOF'
test: fix remaining specs for error handling removal

Update test expectations to match new fail_track behavior.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary of Changes

| Generator | Change |
|-----------|--------|
| validate_contract | `raise` → `return false`, remove ON_FAILURES "raise" |
| build_contract | Remove class existence `raise NameError` |
| cache_read | Remove "raise" from ON_MISS_BEHAVIOR |
| cache_fetch | Remove "raise" from FALLBACK_ERROR_STRATEGIES |
| cache_delete | Skip silently instead of raise on large pattern |
| enqueue_job | Remove class existence `raise NameError` |
| schedule_job | Remove all `raise NameError` and `raise ArgumentError` |
| send_email | Remove unused ERROR_STRATEGIES constant |
| calculate | Remove "error" from EMPTY_BEHAVIORS |
| merge_data | Remove "error" from ON_CONFLICT |
| compress_files | Remove unused ERROR_STRATEGIES constant |
| parse_csv | Remove unused ERROR_STRATEGIES constant |
| bulk_import | Remove "raise" from ON_DUPLICATE_KEY |
| destroy_model | `raise "password mismatch"` → `return false` |
| parallel_for_each | Remove "first_error" from ERROR_AGGREGATIONS |

| JS Schema | Change |
|-----------|--------|
| validation_actions.js | Remove onFailure raise, includeWarnings, strictMode, errorVar |
| caching_actions.js | Remove raise from onMiss, remove fallbackErrorStrategy |
| data_actions.js | Remove error from emptyCollectionBehavior, onConflict |
| model_actions.js | Remove raise from onDuplicateKey, onConflict |
