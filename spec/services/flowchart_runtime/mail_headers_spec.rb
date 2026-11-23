# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::MailHeaders do
  it "accepts a single valid address and array form" do
    expect(described_class.addresses!("to@example.test")).to eq("to@example.test")
    expect(described_class.addresses!(["to@example.test", "cc@example.test"]))
      .to eq(["to@example.test", "cc@example.test"])
  end

  it "rejects CR/LF in recipient values before Mail writes header lines" do
    expect { described_class.addresses!("to@example.test\nBcc: attacker@evil.test") }
      .to raise_error(described_class::Error, I18n.t("code_generator_communication.invalid_recipients"))
  end

  it "collapses control characters in unstructured fields" do
    expect(described_class.unstructured("Hello\r\nBcc: attacker@evil.test")).to eq("Hello Bcc: attacker@evil.test")
  end

  it "rejects header names that are not RFC tokens" do
    expect { described_class.fields({ "X-Trace\nBcc" => "trace" }) }
      .to raise_error(described_class::Error, I18n.t("code_generator_communication.invalid_headers"))
  end

  it "sanitizes configured recipient keys and leaves other kwargs unchanged" do
    expect(described_class.recipients(cc: "cc@example.test", extra: 1))
      .to eq(cc: "cc@example.test", extra: 1)
  end

  it "localizes invalid public input in Simplified Chinese" do
    I18n.with_locale(:"zh-CN") do
      expect { described_class.addresses!("") }
        .to raise_error(described_class::Error, "至少需要一个有效的收件人邮箱地址")
    end
  end
end
