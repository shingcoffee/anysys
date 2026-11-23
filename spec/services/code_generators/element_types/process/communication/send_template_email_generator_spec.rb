# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::SendTemplateEmailGenerator do
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

  it "is version 2.2.0" do
    expect(described_class._metadata[:version]).to eq("2.2.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"send_template_email.failed", Email::Errors::Error) do
          ctx[:email_message_id] = FlowchartRuntime::TemplateEmail.deliver(
            ctx,
            to: FlowchartRuntime::Step.dig(ctx[:user], :email),
            template_id: "1",
            vars: {}
          )
        end
      end
    RUBY
  end

  it "emits an explicit locale expression when configured" do
    expect(generated_step(described_class.sample_input.merge("locale" => '"zh-CN"'))).to include(
      'locale: "zh-CN"'
    )
  end

  it "builds vars from mapping rows" do
    src = generated_step(described_class.sample_input.merge(
      "vars" => [{ "key" => "name", "value" => "ctx[:user_name]" }, { "key" => "company", "value" => "Acme Corp" }]
    ))
    expect(src).to include("vars: {name: ctx[:user_name], company: \"Acme Corp\"}")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let!(:template) do
      create(
        :email_template,
        customer: customer,
        name: "welcome",
        subject: "Hi #{platform_token('first_name')}",
        body_html: "<p>Hello #{platform_token('first_name')}</p>"
      )
    end
    let!(:credential) { create(:email_credential, mode: "sandbox") }

    before { allow(Emails::DeliverMessageJob).to receive(:perform_later) }

    it "sends through the gateway and records the message id" do
      ctx = { customer_id: customer.id, user: { "email" => "user@example.test" }, errors: [] }
      config = described_class.sample_input.merge(
        "templateId" => template.id,
        "to" => "user.email",
        "vars" => [{ "key" => "first_name", "value" => "Ada" }]
      )

      expect {
        result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
        expect(result[:validation_errors]).to eq([])
        expect(result[:outcome]).to eq(ctx[:email_message_id])
      }.to change(Emails::Message, :count).by(1)

      message = Emails::Message.last
      expect(message.customer_id).to eq(customer.id)
      expect(message.to).to eq("user@example.test")
      expect(message.email_template_id).to eq(template.id)
      expect(ctx[:email_message_id]).to eq(message.id)
      expect(Emails::DeliverMessageJob).to have_received(:perform_later)
    end

    it "sends inside the configured locale" do
      ctx = { customer_id: customer.id, user: { "email" => "user@example.test" }, errors: [] }
      config = described_class.sample_input.merge(
        "templateId" => template.id,
        "to" => "user.email",
        "locale" => '"zh-CN"',
        "vars" => [{ "key" => "first_name", "value" => "Ada" }]
      )
      seen = nil
      allow(I18n).to receive(:with_locale).and_wrap_original do |original, locale, &block|
        seen = locale
        original.call(locale, &block)
      end

      result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
      expect(result[:outcome]).to eq(ctx[:email_message_id])
      expect(seen.to_s).to eq("zh-CN")
    end

    it "fails with a translated message when the gateway rejects the send" do
      ctx = { customer_id: customer.id, user: { "email" => "user@example.test" }, errors: [] }
      config = described_class.sample_input.merge("templateId" => 0, "to" => "user.email")

      result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_template_email.failed"))
    end
  end
end
