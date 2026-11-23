# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime::Token" do
  subject(:facade) { "FlowchartRuntime::Token".constantize }

  it "generates a Base58 token through the base58 gem" do
    expect(facade.base58(bytes: 16)).to match(/\A[1-9A-HJ-NP-Za-km-z]+\z/)
  end

  it "rejects non-positive byte lengths" do
    expect { facade.base58(bytes: 0) }.to raise_error do |error|
      expect(error.class.name).to eq("FlowchartRuntime::Token::Error")
      expect(error.message).to eq("bytes must be positive")
    end
  end

  it "validates byte lengths without a broad argument-error rescue" do
    source = Rails.root.join("app/services/flowchart_runtime/token.rb").read

    expect(source).not_to match(/rescue\s+(?:ArgumentError|TypeError)/)
  end

  it "round-trips a JSON payload through MessageVerifier with purpose and expiry" do
    token = facade.sign({ "sub" => "user-1" }, key: "secret", purpose: "password_reset", expires_in: "1h")
    expect(facade.verify(token, key: "secret", purpose: "password_reset")).to eq("sub" => "user-1")
    expect { facade.verify(token, key: "secret", purpose: "other") }
      .to raise_error(facade::InvalidToken)
  end

  it "returns nil from verify_or_nil for a tampered token without raising InvalidToken" do
    expect(facade.verify_or_nil("not-a-token", key: "secret")).to be_nil
  end
end
