# frozen_string_literal: true

module Operations
  class Outcome < Struct.new(
    :status, :operation, :data, :plan, :violations, :effects, :invocation, :replayed,
    keyword_init: true
  )
    OK_STATUSES = %w[succeeded confirmation_required dry_run].freeze
    HTTP_STATUSES = {
      "succeeded" => 200,
      "confirmation_required" => 202,
      "dry_run" => 200,
      "invalid" => 422,
      "conflict" => 409,
      "forbidden" => 403,
      "failed" => 500
    }.freeze
    PAYLOAD_KEYS = {
      "succeeded" => "data",
      "confirmation_required" => "plan",
      "dry_run" => "plan",
      "invalid" => "errors",
      "conflict" => "errors",
      "forbidden" => "errors",
      "failed" => "errors"
    }.freeze

    def initialize(status:, operation: nil, data: nil, plan: nil, violations: [], effects: nil, invocation: nil, replayed: false)
      super(
        status: status.to_s,
        operation: operation,
        data: data,
        plan: plan,
        violations: Array.wrap(violations),
        effects: effects,
        invocation: invocation,
        replayed: replayed
      )
    end

    def self.succeeded(operation:, data: nil, effects: nil, invocation: nil, replayed: false)
      new(status: "succeeded", operation: operation, data: data, effects: effects, invocation: invocation, replayed: replayed)
    end

    def self.confirmation_required(operation:, plan:, invocation: nil, replayed: false)
      new(status: "confirmation_required", operation: operation, plan: plan, invocation: invocation, replayed: replayed)
    end

    def self.dry_run(operation:, plan:, replayed: false)
      new(status: "dry_run", operation: operation, plan: plan, replayed: replayed)
    end

    def self.invalid(operation:, violations:, invocation: nil, replayed: false)
      new(status: "invalid", operation: operation, violations: violations, invocation: invocation, replayed: replayed)
    end

    def self.conflict(operation:, violations:, invocation: nil, replayed: false)
      new(status: "conflict", operation: operation, violations: violations, invocation: invocation, replayed: replayed)
    end

    def self.forbidden(operation:, violations:, invocation: nil, replayed: false)
      new(status: "forbidden", operation: operation, violations: violations, invocation: invocation, replayed: replayed)
    end

    def self.failed(operation:, violations:, invocation: nil, replayed: false)
      new(status: "failed", operation: operation, violations: violations, invocation: invocation, replayed: replayed)
    end

    def ok?
      OK_STATUSES.include?(status)
    end

    def http_status
      HTTP_STATUSES.fetch(status, 500)
    end

    def to_tool_payload(attempts_remaining: nil)
      payload = {
        "ok" => ok?,
        "status" => status,
        "operation" => operation
      }
      key = PAYLOAD_KEYS[status]
      payload[key] = payload_value(key) if key
      payload["attempts_remaining"] = attempts_remaining unless attempts_remaining.nil?
      payload["next_step"] = next_step(attempts_remaining: attempts_remaining)
      payload
    end

    def to_problem
      {
        "type" => "urn:anysys:problem:#{status}",
        "title" => I18n.t("operations.problems.#{status}"),
        "status" => http_status,
        "detail" => next_step,
        "operation" => operation,
        "errors" => violations.map(&:as_json)
      }
    end

    def as_stored_result
      {
        "status" => status,
        "operation" => operation,
        "data" => data,
        "plan" => plan,
        "effects" => effects,
        "violations" => violations.map(&:as_json)
      }
    end

    def self.from_stored_result(result, invocation:, replayed: true)
      hash = (result || {}).stringify_keys
      new(
        status: hash["status"],
        operation: hash["operation"],
        data: hash["data"],
        plan: hash["plan"],
        effects: hash["effects"],
        violations: Array(hash["violations"]).map { |row| from_stored_violation(row) },
        invocation: invocation,
        replayed: replayed
      )
    end

    def self.from_stored_violation(row)
      attrs = row.to_h.stringify_keys
      details = attrs.except("pointer", "code", "message", "resolution")
      Violation.new(
        pointer: attrs["pointer"],
        code: attrs["code"],
        details: details,
        resolution: attrs["resolution"]
      )
    end

    private

    def payload_value(key)
      case key
      when "data" then data
      when "plan" then plan
      when "errors" then violations.map(&:as_json)
      end
    end

    def next_step(attempts_remaining: nil)
      interpolations = { operation: operation }
      return I18n.t("operations.guidance.#{status}", **interpolations) unless status == "invalid"

      resolutions = violations.map(&:resolution).uniq.select { |item| Violation::RESOLUTIONS.include?(item) }
      text = if resolutions.empty?
        I18n.t("operations.guidance.invalid", **interpolations)
      else
        resolutions.map { |item| I18n.t("operations.guidance.#{item}", **interpolations) }.join(" ")
      end
      return text if attempts_remaining.nil?

      text + I18n.t("operations.guidance.attempts_remaining", attempts: attempts_remaining)
    end
  end
end
