# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::MessageAdmission do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:sms_credential) }
  let!(:template) { create(:sms_template) }
  let(:vars) { { "code" => "1234", "minutes" => 5 } }

  before { enable_module!("sms", customer, name: "SMS") }

  def admit(**options)
    Sms::Activities::Send.call(**{ customer: customer, to: "+8613800138000", template_key: template.key,
                                  vars: vars, idempotency_key: "identity" }.merge(options))
  end

  it "replays canonical phone, variable order and symbol keys before all mutable prerequisites" do
    first = admit(to: "13800138000")
    template.update!(status: "retired", variables: ["changed"], provider_template_codes: { "aliyun" => "SMS_NEW" })
    credential.update!(status: "disabled")
    FeatureModules::CustomerAssignment.where(customer_id: customer.id).update_all(status: 1)
    Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: first.to)
    allow(Sms::Activities::Send).to receive(:daily_cap_for).and_return(0)
    expect(Sms::Template).not_to receive(:active)
    expect(Sms::CredentialResolver).not_to receive(:call)
    expect(FeatureModules::Module).not_to receive(:enabled?)
    expect(Sms::Quota).not_to receive(:synchronize)
    expect(Sms::OptOut).not_to receive(:opted_out?)

    expect(admit(vars: { minutes: 5, code: "1234" }).id).to eq(first.id)
    expect(first.reload.status).to eq("queued")
  end

  it "rejects a key reused with a different recipient, template, payload or explicit selection/expiry" do
    admit
    [{ to: "+8613800138001" }, { template_key: "different" }, { vars: vars.merge("code" => "5678") },
     { provider: "aliyun" }, { mode: "sandbox" }, { expires_at: 1.hour.from_now }].each do |change|
      expect { admit(**change) }.to raise_error(Sms::Errors::IdempotencyConflict)
    end
    expect(Sms::Message.where(customer_id: customer.id).count).to eq(1)
  end

  it "binds explicit expiry to the same instant and leaves omitted expiry stable on replay" do
    at = 10.minutes.from_now
    first = admit(expires_at: at)
    expect(admit(expires_at: at.utc).id).to eq(first.id)
    expect { admit }.to raise_error(Sms::Errors::IdempotencyConflict)
  end

  it "does not share idempotency keys across customers" do
    first = admit
    other = create(:customer)
    enable_module!("sms", other, name: "SMS")
    expect(admit(customer: other).id).not_to eq(first.id)
  end

  it "requires module enablement for every new send including opted-out recipients" do
    FeatureModules::CustomerAssignment.where(customer_id: customer.id).update_all(status: 1)
    expect { admit }.to raise_error(Sms::Errors::ModuleDisabled)
    Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: "+8613800138000")
    expect { admit }.to raise_error(Sms::Errors::ModuleDisabled)
    expect(Sms::Message.where(customer_id: customer.id).count).to eq(0)
  end

  it "checks the racing winner's fingerprint after the unique index rejects insertion" do
    winner = admit
    allow(described_class).to receive(:existing).and_return(nil, nil, winner)
    allow(Sms::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
    allow(Sms::Quota).to receive(:check_rate_limit!)

    expect { admit(vars: vars.merge("code" => "other")) }.to raise_error(Sms::Errors::IdempotencyConflict)
    expect(Sms::Message.where(customer_id: customer.id).count).to eq(1)
  end

  it "also compares a racing winner under the quota lock before template validation" do
    winner = admit
    allow(described_class).to receive(:existing).and_return(nil, winner)
    template.update!(status: "retired")
    expect { admit(to: "+8613800138001") }.to raise_error(Sms::Errors::IdempotencyConflict)
  end

  it "validates arbitrary idempotency values as bounded strings, counting bytes" do
    expect(described_class).not_to receive(:existing)
    [false, 123, [], {}, :key, "k" * 129, "中" * 43, " " * 129].each do |key|
      expect { admit(idempotency_key: key) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "accepts the shared 128-byte idempotency key boundary" do
    expect(admit(idempotency_key: "k" * 128).idempotency_key.bytesize).to eq(128)
  end

  it "treats blank strings as absent without turning arbitrary objects into keys" do
    first = admit(idempotency_key: " ")
    second = admit(to: "+8613800138001", idempotency_key: "")
    expect(second.id).not_to eq(first.id)
    expect([first.idempotency_key, second.idempotency_key]).to eq([nil, nil])
  end

  it "rejects ambiguous double keys, nested/non-object payloads, non-scalars and nonfinite numbers before replay" do
    admit
    expect(described_class).not_to receive(:existing)
    expect(Digest::SHA256).not_to receive(:hexdigest)
    [{ code: "1234", "code" => "1234", minutes: 5 }, { code: { nested: "x" } }, { code: [1] },
     { code: true }, { code: nil }, { code: Float::NAN }, [], "vars"].each do |payload|
      expect { admit(vars: payload) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "normalizes nil vars to an empty object and replays it as {} after retirement" do
    template.update!(variables: [])
    first = admit(vars: nil)
    expect(first.vars).to eq({})
    expect(first.metadata.dig("template_snapshot", "vars")).to eq({})
    template.update!(status: "retired")
    expect(Sms::Template).not_to receive(:active)
    expect(Sms::Quota).not_to receive(:synchronize)
    expect(admit(vars: {}).id).to eq(first.id)
    expect(admit(vars: nil).id).to eq(first.id)
    expect { admit(vars: { code: "changed" }) }.to raise_error(Sms::Errors::IdempotencyConflict)
  end

  it "reports nil vars as missing required keys for a new template that needs variables" do
    expect { admit(vars: nil) }.to raise_error(Sms::Errors::TemplateVarsInvalid, /missing required keys/)
  end

  it "checks template format and bytes before replay SQL or fingerprint allocation" do
    admit
    expect(described_class).not_to receive(:existing)
    expect(Sms::Template).not_to receive(:active)
    expect(Digest::SHA256).not_to receive(:hexdigest)
    [nil, "", " ", "Upper_case", "invalid key", "verify-code", "界", "a" * 129, [], {}].each do |key|
      expect { admit(template_key: key) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "rejects blank values, invalid variable keys and oversized scalar/count inputs before copying or JSON" do
    admit
    expect(described_class).not_to receive(:existing)
    expect(Digest::SHA256).not_to receive(:hexdigest)
    expect(JSON).not_to receive(:generate)
    huge_integer = 1 << (Sms::SendStandards::MAX_VALUE_BYTES * 4 + 1)
    [{ code: "" }, { code: " " }, { "" => "value" }, { " " => "value" },
     { ("a" * 129) => "value" }, { ("界" * 43) => "value" },
     { code: "a" * 1_025 }, { code: "界" * 342 }, { code: huge_integer },
     (1..65).to_h { |i| ["v#{i}", "value"] }].each do |payload|
      expect { admit(vars: payload) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "permits the numeric types in SendStandards and rejects other Numeric subclasses before normalization" do
    [1234, 0, 1.25, BigDecimal("1.25")].each_with_index do |value, i|
      message = admit(to: "+86138001381#{i.to_s.rjust(2, '0')}", idempotency_key: "number-#{i}",
                      vars: { code: value, minutes: 5 })
      expect(message.status).to eq("queued")
      expect(admit(to: message.to, idempotency_key: "number-#{i}", vars: { "minutes" => 5, "code" => value }).id).to eq(message.id)
    end
    expect(described_class).not_to receive(:existing)
    expect(JSON).not_to receive(:generate)
    [Rational(1, 2), Complex(1, 2), Numeric.new, Float::INFINITY, BigDecimal("NaN")].each do |value|
      expect { admit(vars: { code: value, minutes: 5 }) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "admits the variable-count and per-value boundaries" do
    payload = (1..64).to_h { |i| ["v#{i}", "value"] }
    payload["v1"] = "a" * 1_024
    template.update!(variables: payload.keys)
    expect(admit(vars: payload).vars).to eq(payload)
  end

  it "bounds total JSON bytes including escaping before fingerprinting or a conflicting replay lookup" do
    payload = (0..7).to_h { |i| ["v#{i}", "a" * 1_024] }
    payload["v7"] = ""
    payload["v7"] = "a" * (Sms::SendStandards::MAX_PAYLOAD_BYTES - JSON.generate(payload).bytesize)
    expect(JSON.generate(payload).bytesize).to eq(8_192)
    template.update!(variables: payload.keys)
    first = admit(vars: payload)
    expect(admit(vars: payload.to_a.reverse.to_h).id).to eq(first.id)
    expect(described_class).not_to receive(:existing)
    expect(Digest::SHA256).not_to receive(:hexdigest)
    oversized = payload.merge("v7" => payload.fetch("v7") + "a")
    escaped = (1..4).to_h { |i| ["v#{i}", "\x01" * 512] }
    [oversized, escaped].each do |vars|
      expect { admit(vars: vars) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "rejects invalid recipient types and expiry values predictably" do
    [nil, 13800138000, {}, []].each do |phone|
      expect { admit(to: phone) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
    expect { admit(expires_at: "later") }.to raise_error(Sms::Errors::TemplateVarsInvalid)
  end

  it "validates invalid/non-UTF8 keys and variables without leaking fingerprint encoding errors" do
    invalid = "\xFF".dup.force_encoding(Encoding::UTF_8)
    non_utf8 = "\xE9".dup.force_encoding(Encoding::ISO_8859_1)
    [invalid, non_utf8].each do |string|
      expect { admit(idempotency_key: string) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
      expect { admit(provider: string) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
      expect { admit(vars: { string => "value" }) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
      expect { admit(vars: vars.merge("code" => string)) }.to raise_error(Sms::Errors::TemplateVarsInvalid)
    end
  end

  it "snapshots selected content and defaults expiry to one hour" do
    travel_to(Time.current.change(usec: 0)) do
      message = admit
      expect(message.expires_at).to eq(1.hour.from_now)
      expect(message.metadata).to include("credential_id" => credential.id, "credential_mode" => credential.mode)
      expect(message.metadata.fetch("template_snapshot")).to include(
        "provider" => "aliyun", "provider_code" => template.provider_code("aliyun"),
        "required_vars" => template.required_vars, "vars" => vars
      )
    end
  end
end
