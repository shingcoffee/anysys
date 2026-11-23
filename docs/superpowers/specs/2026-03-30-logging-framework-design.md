# Logging Framework Design

## Overview

Replace ad-hoc `Rails.logger` calls across the application with a consistent, tenant-aware tagged logging framework following Rails 8 best practices.

## Architecture

Two components sharing one implementation:

- **`AppLogger`** (module) — core implementation, used directly by generated code and initializers
- **`Loggable`** (concern) — included in controllers/services, provides `log_info`/`log_warn`/`log_error`/`log_debug` instance methods with automatic class-name tagging

Both produce tagged plaintext via `Rails.logger.tagged(...)`.

### Output Format

```
[customer:12345678] [DynamicController] Executing: flowchart=Create Product (550e8400...)
[customer:12345678] [ActivityTracer] Built activity class: CreateProductActivity
[ActivityClassBuilder] Failed to build activity class - RuntimeError: bad code
```

Tenant tag (`customer:ID`) appears only when `Current.customer` is set. Source tag (class name) always present.

## Components

### AppLogger — `app/services/app_logger.rb`

Module with four public methods: `info`, `warn`, `error`, `debug`. Each accepts a message string and optional `source:` keyword.

```ruby
module AppLogger
  module_function

  def info(message, source: nil)  = log(:info, message, source: source)
  def warn(message, source: nil)  = log(:warn, message, source: source)
  def error(message, source: nil) = log(:error, message, source: source)
  def debug(message, source: nil) = log(:debug, message, source: source)

  def log(level, message, source: nil)
    tags = build_tags(source)
    if tags.any?
      Rails.logger.tagged(*tags) { Rails.logger.public_send(level, message) }
    else
      Rails.logger.public_send(level, message)
    end
  end

  def build_tags(source)
    tags = []
    tags << "customer:#{Current.customer_id}" if Current.customer?
    tags << source if source
    tags
  end
end
```

### Loggable — `app/models/concerns/loggable.rb`

Concern that delegates to `AppLogger` with auto-derived source name.

```ruby
module Loggable
  extend ActiveSupport::Concern

  private

  def log_info(message)  = AppLogger.info(message, source: log_source)
  def log_warn(message)  = AppLogger.warn(message, source: log_source)
  def log_error(message) = AppLogger.error(message, source: log_source)
  def log_debug(message) = AppLogger.debug(message, source: log_source)

  def log_source
    self.class.name.demodulize
  end
end
```

## Refactoring Scope

### Services — replace `Rails.logger.X("ClassName: ...")` with `include Loggable` + `log_X(...)`

| File | Log calls |
|------|-----------|
| `app/controllers/dynamic_controller.rb` | Remove custom `log_info`/`log_error` methods, add `include Loggable` |
| `app/services/activity_tracer.rb` | 7 `Rails.logger.debug/error` calls → `log_debug`/`log_error` |
| `app/services/concerns/activity_class_builder.rb` | 3 `Rails.logger.error/warn` calls → `log_error`/`log_warn` |
| `app/services/dynamic_class_loader.rb` | 2 `Rails.logger.warn` calls → `log_warn` |
| `app/services/activity_diagram_generator.rb` | 1 `Rails.logger.error` call → `log_error` |
| `app/services/calculation_evaluator.rb` | 1 `Rails.logger.error` call → `log_error` |
| `app/services/context_sanitizer.rb` | 1 `Rails.logger.warn` call → `log_warn` |
| `app/services/code_generators/generator_registry.rb` | 1 `Rails.logger.warn` call → `log_warn` |
| `app/services/activity_generator.rb` | 1 `Rails.logger.warn` call → `log_warn` |

### Initializers — use `AppLogger` directly (no class to include into)

| File | Change |
|------|--------|
| `config/initializers/feature_modules.rb` | `Rails.logger.warn(...)` → `AppLogger.warn(..., source: "FeatureModules")` |

### Code generators — change generated output from `Rails.logger` to `AppLogger`

| Generator | Generated code change |
|-----------|---------------------|
| `app/services/code_generators/element_types/error_handler/error_handler_generator.rb` | `Rails.logger.error(...)` → `AppLogger.error(..., source: "Activity")` |
| `app/services/code_generators/element_types/process/data_operations/log_generator.rb` | `Rails.logger.#{level}(...)` → `AppLogger.#{level}(..., source: "Activity")` |

### Config — no changes needed

Production already uses `ActiveSupport::TaggedLogging` with `request_id` tag. The `AppLogger` module layers tenant/source tags on top of whatever Rails has configured. No middleware or formatter changes required.

## Testing

### AppLogger specs — `spec/services/app_logger_spec.rb`

- Logs at each level (info, warn, error, debug)
- Tags with source when provided
- Tags with `customer:ID` when `Current.customer` is set
- Omits tenant tag when no customer is set
- Works with no source and no customer (bare message)

### Loggable specs — `spec/models/concerns/loggable_spec.rb`

- Provides `log_info`/`log_warn`/`log_error`/`log_debug` to including class
- Auto-derives source from class name via `demodulize`
- Delegates to `AppLogger`

### Update existing specs

- `spec/requests/dynamic_spec.rb` — no changes (tests behavior, not log output)
- `spec/services/activity_diagram_generator_spec.rb` — update `expect(Rails.logger).to receive(:error)` to match new tagged pattern
- `spec/services/code_generators/element_types/process/data_operations/log_generator_spec.rb` — expect `AppLogger` in generated code
- `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb` — expect `AppLogger` in generated code
- `spec/services/activity_generator_spec.rb` — update expectations for `AppLogger` in generated output
