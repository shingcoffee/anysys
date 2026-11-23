# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::SendSmsGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "is version 1.1.0" do
    expect(described_class._metadata[:version]).to eq("1.1.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"send_sms.failed", FlowchartRuntime::SmsDelivery::Error) do
          ctx[:sms_message_id] = FlowchartRuntime::SmsDelivery.deliver(
            ctx,
            customer: Customer.find_by(id: ctx[:customer_id]),
            to: FlowchartRuntime::Step.dig(ctx[:model], :phone),
            template_key: "verify_code"
          )
        end
      end
    RUBY
  end

  it "builds vars from mapping rows as expressions" do
    src = generated_step(described_class.sample_input.merge(
      "vars" => [{ "key" => "code", "value" => "ctx[:otp]" }, { "key" => "minutes", "value" => '"5"' }]
    ))
    expect(src).to include("vars: {code: ctx[:otp], minutes: \"5\"}")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let!(:credential) { create(:sms_credential, provider: "aliyun", mode: "sandbox") }
    let!(:template) do
      create(:sms_template, key: "verify_code", variables: %w[code minutes],
                            provider_template_codes: { "aliyun" => "SMS_1" })
    end
    let(:phone) { "+8613800138000" }
    let(:config) do
      described_class.sample_input.merge(
        "templateKey" => "verify_code",
        "to" => "model.phone",
        "vars" => [{ "key" => "code", "value" => '"1234"' }, { "key" => "minutes", "value" => '"5"' }]
      )
    end

    before do
      enable_module!("sms", customer, name: "SMS")
      allow(Sms::DeliverMessageJob).to receive(:perform_later)
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).and_return(
        { vendor_message_id: "BIZ-1", raw: { "Code" => "OK", "BizId" => "BIZ-1" } }
      )
    end

    def ctx_for(owner, number = phone)
      { customer_id: owner.id, model: { "phone" => number }, errors: [] }
    end

    it "admits a tenant ledger row for the run's customer only" do
      ctx = ctx_for(customer)
      expect {
        result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
        expect(result[:validation_errors]).to eq([])
        expect(result[:outcome]).to eq(ctx[:sms_message_id])
      }.to change(Sms::Message, :count).by(1)

      message = Sms::Message.last
      expect(message.customer_id).to eq(customer.id)
      expect(message.to).to eq(phone)
      expect(message.template_key).to eq("verify_code")
      expect(ctx[:sms_message_id]).to eq(message.id)
      expect(Sms::Message.where(customer_id: other.id).count).to eq(0)
    end

    it "fails with a translated suppression message and still records the tenant row" do
      Sms::OptOut.record_global!(phone_e164: phone, provider: "twilio", reason: "inbound:STOP")
      ctx = ctx_for(customer)

      expect {
        result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
        expect(result[:outcome]).to be(false)
      }.to change(Sms::Message, :count).by(1)

      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_sms.suppressed"))
      expect(Sms::Message.last).to have_attributes(customer_id: customer.id, status: "suppressed")
      expect(Sms::Message.where(customer_id: other.id).count).to eq(0)
    end

    it "fails with a translated quota message" do
      ctx = ctx_for(customer)
      CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)

      again = ctx_for(customer)
      result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: again)
      expect(result[:outcome]).to be(false)
      expect(again[:errors]).to include(I18n.t("flowchart_runtime.errors.send_sms.quota"))
    end
  end

  it "keeps English and zh-CN locale keys in parity" do
    english = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_sms_document.en.yml"))
    chinese = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_sms_document.zh-CN.yml"))
    flatten = lambda do |value, prefix = ""|
      return { prefix => true } unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, child), acc|
        acc.merge!(flatten.call(child, prefix.empty? ? key.to_s : "#{prefix}.#{key}"))
      end
    end
    expect(flatten.call(chinese.fetch("zh-CN")).keys).to match_array(flatten.call(english.fetch("en")).keys)
  end
end
