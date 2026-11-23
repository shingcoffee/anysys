# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::EncryptDataGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "ssn", "resultVar" => "encrypted", "keySource" => "ctx", "keyPath" => "cipher_key",
      "encoding" => "base64" }
  end
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"encrypt_data.failed", FlowchartRuntime::Cipher::Error) do
          cipher_key = FlowchartRuntime::Cipher.resolve_key do
            Rails.application.credentials.dig(:primary_key)
          end
          ctx[:encrypted] = FlowchartRuntime::Cipher.encrypt_value(
            ctx[:sensitive_data].to_s,
            key: cipher_key,
            encoding: "base64"
          )
          true
        end
      end
    RUBY
  end

  it "generates a derived-key step namespaced by customer_id" do
    config = described_class.sample_input.merge(
      "keySource" => "derived", "deriveKeyFrom" => "master_secret", "deriveKeySalt" => "user_data_v1"
    )
    src = generated_step(config)
    expect(src).to include("FlowchartRuntime::Cipher.key_from_passphrase(")
    expect(src).to include('salt: "flowchart.cipher.#{ctx[:customer_id]}." + "user_data_v1"')
  end

  it "emits encrypt_value and never decrypt" do
    expect(body).to include("FlowchartRuntime::Cipher.encrypt_value")
    expect(body).not_to include("decrypt_value")
    expect(body).to include("ctx[:cipher_key]")
  end

  describe "behaviour" do
    it "emits the configured purpose" do
      expect(body(base.merge("purpose" => "user_data"))).to include('purpose: "user_data"')
      expect(body(base.merge("purpose" => "user_data"))).not_to eq(body(base))
    end

    it "encrypts plaintext with a ctx key" do
      ctx = { ssn: "123-45-6789", cipher_key: "test-secret-key-material" }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:encrypted]).to be_present
      expect(FlowchartRuntime::Cipher.decrypt_value(ctx[:encrypted], key: ctx[:cipher_key], encoding: :base64))
        .to eq("123-45-6789")
    end

    it "records a translated failure when the key is missing" do
      ctx = { ssn: "secret", cipher_key: "" }
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not encrypt")
    end
  end
end
