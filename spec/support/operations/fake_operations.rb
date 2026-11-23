# frozen_string_literal: true

module Operations
  module FakeVocabulary
    module_function

    def resolve(name, context)
      case name.to_s
      when "colors"
        values = ["red", "blue"]
        values += ["tenant-#{context.customer.id}"] if context&.customer
        { values: values, descriptions: values.to_h { |value| [value, "The #{value} option."] } }
      when "nullable_colors"
        { values: ["red"], descriptions: { "red" => "Red." } }
      when "max_items"
        5
      else
        raise ArgumentError, "unknown vocabulary: #{name}"
      end
    end
  end

  class FakeEcho < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_echo"
    version 1
    title "Fake echo"
    summary "Echoes the input for framework specs."
    schema "echo.json"
    shared_defs "echo.defs.json"
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input, effects: [{ "kind" => "echo" }])
    end
  end

  class FakeUpdate < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_update"
    version 1
    title "Fake update"
    summary "Parks a plan for confirmation."
    schema "echo.json"
    shared_defs "echo.defs.json"
    annotations destructive: true, confirmation: :always

    def plan(input)
      [{ "kind" => "echo", "name" => input["name"] }]
    end

    def snapshot(input)
      { "name" => input["name"] }
    end

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeRead < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_read"
    version 1
    title "Fake read"
    summary "A read-only operation that is not audited."
    schema "echo.json"
    shared_defs "echo.defs.json"
    annotations read_only: true, confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeUnavailable < FakeEcho
    key "fake_unavailable"
    title "Fake unavailable"
    summary "Never available."

    def self.available?(_context)
      false
    end
  end

  class FakeDomainError < FakeEcho
    key "fake_domain_error"
    title "Fake domain error"
    summary "Raises RecordInvalid from perform."

    def perform(_input)
      record = OperationInvocation.new
      record.errors.add(:base, "name is reserved")
      raise ActiveRecord::RecordInvalid, record
    end
  end

  class FakeBoom < FakeEcho
    key "fake_boom"
    title "Fake boom"
    summary "Raises StandardError from perform."

    def perform(_input)
      raise StandardError, "boom"
    end
  end

  class FakeWriteThenFail < FakeEcho
    key "fake_write_then_fail"
    title "Fake write then fail"
    summary "Writes a row, then reports an invalid outcome."

    def perform(input)
      OperationInvocation.create!(customer_id: context.customer.id, operation: "partial_write", operation_version: 1,
                                  channel: "system", status: "succeeded")
      Outcome.invalid(operation: self.class.key, violations: [Violation.new(pointer: "/name", code: "schema.invalid")])
    end
  end

  class FakeConflictOnConfirm < FakeUpdate
    key "fake_conflict_on_confirm"
    title "Fake conflict on confirm"
    summary "Validates at proposal time, reports a conflict when re-validated on approval."

    def validate(_input)
      return [] unless context.confirmed

      [Violation.new(pointer: "/name", code: "conflict.version_changed")]
    end
  end

  class FakeStale < FakeUpdate
    key "fake_stale"
    title "Fake stale"
    summary "Always reports a stale snapshot."

    def stale?(_snapshot)
      true
    end
  end

  class FakeSemantic < FakeEcho
    key "fake_semantic"
    title "Fake semantic"
    summary "Fails semantic validation."

    def validate(_input)
      [Violation.new(pointer: "/name", code: "schema.invalid", details: {})]
    end
  end

  class FakeValidateBoom < FakeEcho
    key "fake_validate_boom"
    title "Fake validate boom"
    summary "Raises from validate."

    def validate(_input)
      raise StandardError, "secret internals"
    end
  end

  class FakeSingleViolation < FakeEcho
    key "fake_single_violation"
    title "Fake single violation"
    summary "Returns one Violation instead of an array."

    def validate(_input)
      Violation.new(pointer: "/name", code: "schema.invalid", details: {})
    end
  end

  class FakeVocab < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_vocab"
    version 1
    title "Fake vocabulary"
    summary "Resolves vocabulary slots."
    schema "vocab.json"
    vocabulary FakeVocabulary
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeNested < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_nested"
    version 1
    title "Fake nested"
    summary "Nested anyOf and if-then."
    schema "nested.json"
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeKeywords < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_keywords"
    version 1
    title "Fake keywords"
    summary "Keyword mapping coverage."
    schema "keywords.json"
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeLintClean < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_lint_clean"
    version 1
    title "Fake lint clean"
    summary "A contract that passes SchemaLint."
    schema "lint_clean.json"
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeLintTypeProperty < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_lint_type_property"
    version 1
    title "Fake lint type property"
    summary "A property named type and examples that contain type keys."
    schema "lint_type_property.json"
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end

  class FakeLintDirty < Base
    schema_root Rails.root.join("spec/fixtures/operations/schemas")
    key "fake_lint_dirty"
    version 1
    schema "lint_dirty.json"
    annotations confirmation: :never

    def perform(input)
      Outcome.succeeded(operation: self.class.key, data: input)
    end
  end
end
