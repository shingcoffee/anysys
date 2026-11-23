# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::DecryptDataGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "encrypted", "resultVar" => "decrypted", "keySource" => "ctx", "keyPath" => "cipher_key",
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
        FlowchartRuntime::Step.attempt(ctx, :"decrypt_data.failed", FlowchartRuntime::Cipher::Error) do
          cipher_key = FlowchartRuntime::Cipher.resolve_key do
            Rails.application.credentials.dig(:primary_key)
          end
          ctx[:decrypted] = FlowchartRuntime::Cipher.decrypt_value(
            ctx[:encrypted],
            key: cipher_key,
            encoding: "base64"
          )
          true
        end
      end
    RUBY
  end

  it "emits the configured purpose" do
    expect(body(base.merge("purpose" => "user_data"))).to include('purpose: "user_data"')
    expect(body(base.merge("purpose" => "user_data"))).not_to eq(body(base))
  end

  describe "behaviour" do
    it "decrypts a matching ciphertext" do
      key = "test-secret-key-material"
      ciphertext = FlowchartRuntime::Cipher.encrypt_value("secret", key: key, encoding: :base64)
      ctx = { encrypted: ciphertext, cipher_key: key }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:decrypted]).to eq("secret")
    end

    it "records a translated failure for the wrong key" do
      ciphertext = FlowchartRuntime::Cipher.encrypt_value("secret", key: "right-key", encoding: :base64)
      ctx = { encrypted: ciphertext, cipher_key: "wrong-key" }
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not decrypt")
    end
  end
end
