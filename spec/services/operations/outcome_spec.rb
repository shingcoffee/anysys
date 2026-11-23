# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Outcome do
  let(:invalid) do
    described_class.invalid(
      operation: "fake_echo",
      violations: [
        Operations::Violation.new(pointer: "/name", code: "schema.required", details: { property: "name" }),
        Operations::Violation.new(code: "permission.denied")
      ]
    )
  end

  it "treats succeeded, confirmation_required, and dry_run as ok" do
    expect(described_class.succeeded(operation: "fake_echo", data: { "ok" => true })).to be_ok
    expect(described_class.confirmation_required(operation: "fake_update", plan: [])).to be_ok
    expect(described_class.dry_run(operation: "fake_echo", plan: [])).to be_ok
    expect(invalid).not_to be_ok
  end

  it "exposes the RFC 9110 http status for each outcome" do
    expect(described_class.succeeded(operation: "x").http_status).to eq(200)
    expect(described_class.confirmation_required(operation: "x", plan: []).http_status).to eq(202)
    expect(described_class.dry_run(operation: "x", plan: []).http_status).to eq(200)
    expect(invalid.http_status).to eq(422)
    expect(described_class.conflict(operation: "x", violations: []).http_status).to eq(409)
    expect(described_class.forbidden(operation: "x", violations: []).http_status).to eq(403)
    expect(described_class.failed(operation: "x", violations: []).http_status).to eq(500)
  end

  it "builds next_step from the resolutions present on an invalid outcome" do
    payload = invalid.to_tool_payload(attempts_remaining: 2)

    expect(payload["ok"]).to be(false)
    expect(payload["status"]).to eq("invalid")
    expect(payload["errors"].size).to eq(2)
    expect(payload["attempts_remaining"]).to eq(2)
    expect(payload["next_step"]).to include("fake_echo")
    expect(payload["next_step"]).to include("fix_payload")
    expect(payload["next_step"]).to include("blocked")
    expect(payload["next_step"]).to include("2")
  end

  it "renders an RFC 9457 problem document" do
    problem = invalid.to_problem

    expect(problem["type"]).to eq("urn:anysys:problem:invalid")
    expect(problem["status"]).to eq(422)
    expect(problem["title"]).to eq("Invalid operation input")
    expect(problem["operation"]).to eq("fake_echo")
    expect(problem["errors"]).to all(include("code", "message", "pointer", "resolution"))
    expect(problem["detail"]).not_to include("Attempts remaining")
  end

  it "states the attempts left only when they are known" do
    expect(invalid.to_tool_payload(attempts_remaining: 1)["next_step"]).to end_with("Attempts remaining: 1.")
    expect(invalid.to_tool_payload["next_step"]).not_to include("Attempts remaining")
  end

  %w[succeeded confirmation_required dry_run conflict forbidden failed].each do |status|
    it "includes next_step guidance for #{status}" do
      outcome = case status
      when "succeeded" then described_class.succeeded(operation: "fake_echo", data: {})
      when "confirmation_required" then described_class.confirmation_required(operation: "fake_update", plan: [])
      when "dry_run" then described_class.dry_run(operation: "fake_echo", plan: [])
      else described_class.public_send(status, operation: "fake_echo", violations: [])
      end

      expect(outcome.to_tool_payload["next_step"]).to be_present
    end
  end
end
