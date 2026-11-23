# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::BodyLint do
  it "accepts a short body that writes only a declared output" do
    result = described_class.check(<<~RUBY, outputs: %w[total])
      ctx[:total] = ctx[:order]
      return FlowchartRuntime::Step.fail(ctx, :empty, field: :sourceVariable) unless ctx[:order]
      true
    RUBY
    expect(result.ok?).to be(true)
  end

  it "rejects more than 12 significant lines" do
    body = (["x = 1"] * 13).join("\n")
    expect(described_class.check(body).violations).to include(:too_long)
  end

  it "rejects _last_error, result, Timeout, sleep, broad rescue, I18n, and bare locals" do
    expect(described_class.check("ctx[:_last_error] = e.message").violations).to include(:last_error)
    expect(described_class.check("ctx[:result] = 1").violations).to include(:result_key)
    expect(described_class.check("Timeout.timeout(2) { true }").violations).to include(:timeout)
    expect(described_class.check("sleep 1").violations).to include(:sleep)
    expect(described_class.check("rescue => e\n  false").violations).to include(:rescue_e)
    expect(described_class.check("rescue StandardError\n  false").violations).to include(:rescue_standard_error)
    expect(described_class.check("I18n.t('x')").violations).to include(:i18n)
    expect(described_class.check("params.email").violations).to include(:bare_local)
    expect(described_class.check("model.save").violations).to include(:bare_local)
  end

  it "allows params and model as method names, hash keys, symbols, and ctx keys" do
    body = "ctx[:contract].sync\nFlowchartRuntime::Entries.save(ctx, ctx[:contract].model)\n" \
           "x = { model: ctx[:model], \"params\" => ctx[:params] }\ny = :params"
    expect(described_class.check(body).violations).not_to include(:bare_local)
  end

  it "rejects an unchecked fallible call followed by true" do
    expect(described_class.check("entry.save\ntrue").violations).to include(:unchecked_fallible)
    expect(described_class.check("true").violations).not_to include(:unchecked_fallible)
  end

  it "rejects writes to undeclared outputs" do
    expect(described_class.check("ctx[:secret] = 1", outputs: %w[total]).violations)
      .to include(:undeclared_output)
    expect(described_class.check("ctx[:model] = 1", outputs: %w[total]).ok?).to be(true)
  end
end
