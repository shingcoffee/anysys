# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::SendEmailGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generated_step}\nend") }.not_to raise_error
  end

  it "renders the recipients, subject and body as templates over ctx" do
    body = described_class.new({ "config" => described_class.sample_input }, {}).generate_body

    expect(body).to include(
      'FlowchartRuntime::InlineEmail.deliver(ctx, to: "sales@example.com", ' \
      'subject: FlowchartRuntime::Template.render("New order {{ model.order_number }}", ctx)'
    )
    expect(body).not_to include("on_error:")
  end

  it "is version 1.1.0" do
    expect(described_class._metadata[:version]).to eq("1.1.0")
  end

  it "passes on_error only when the step should fail the submission" do
    expect(generated_step(described_class.sample_input.merge("onError" => "fail"))).to include('on_error: "fail"')
  end

  it "emits bcc, locale, attachments and idempotency when configured" do
    src = generated_step(described_class.sample_input.merge(
      "bcc" => "audit@example.com",
      "locale" => '"zh-CN"',
      "attachmentsVariable" => "document",
      "idempotencyKey" => "ctx[:request_id]"
    ))
    expect(src).to include('bcc: "audit@example.com"')
    expect(src).to include('locale: "zh-CN"')
    expect(src).to include("attachments: ctx[:document]")
    expect(src).to include("idempotency_key: ctx[:request_id]")
  end

  it "rejects a body that is not a valid template" do
    expect(errors(described_class.sample_input.merge("body" => "{% if %}")).map(&:code)).to include(:invalid_template)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:order_entity) do
      create(:entity, customer: customer, name: "Order", property_schema: [
        { "name" => "Order number", "name_slug" => "order_number", "html_type" => "text" },
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
      ].to_json)
    end
    let(:order) do
      create(:entity_entry, customer: customer, entity: order_entity, data: { order_number: "A-7", price: 5 }.to_json)
    end
    let(:config) do
      described_class.sample_input.merge(
        "to" => "sales@example.com, {{ model.order_number }}",
        "subject" => "New order {{ model.order_number }}",
        "body" => "Order {{ model.order_number }}\nTotal: {{ model.total }} <b>"
      )
    end

    before { allow(Emails::DeliverMessageJob).to receive(:perform_later) }

    it "sends the email written in the step with the record's stored and calculated values" do
      create(:email_credential, mode: "sandbox")
      ctx = { customer_id: customer.id, model: order, errors: [] }

      expect { @result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx) }
        .to change(Emails::Message, :count).by(1)

      message = Emails::Message.last
      expect(@result[:outcome]).to eq([message.id])
      expect(message).to have_attributes(customer_id: customer.id, to: "sales@example.com", subject: "New order A-7",
                                         body_text: "Order A-7\nTotal: 10 <b>")
      expect(message.body_html).to eq("Order A-7<br>\nTotal: 10 &lt;b&gt;")
      expect(ctx[:email_message_ids]).to eq([message.id])
    end

    it "keeps the submission when the email cannot go out" do
      ctx = { customer_id: customer.id, model: order, errors: [] }
      allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing, "none")

      result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)

      expect([result[:outcome], ctx[:email_message_ids], ctx[:errors]]).to eq([[], [], []])
    end

    it "fails the submission with a translated message when told to" do
      ctx = { customer_id: customer.id, model: order, errors: [] }
      allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing, "none")

      result = CodeGenerators::TestRunner.execute(described_class, config: config.merge("onError" => "fail"), ctx: ctx)

      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_email.failed"))
    end

    it "fails when told to and no recipient is a valid address" do
      ctx = { customer_id: customer.id, model: order, errors: [] }

      result = CodeGenerators::TestRunner.execute(described_class, config: config.merge("to" => "{{ model.missing }}", "onError" => "fail"),
                                                                   ctx: ctx)

      expect(result[:outcome]).to be(false)
    end

    it "stores bcc and attaches a generated document blob" do
      create(:email_credential, mode: "sandbox")
      document = FlowchartRuntime::Document.pdf(
        title: "Invoice", body: "Thanks", filename: "invoice.pdf", customer_id: customer.id
      )
      ctx = { customer_id: customer.id, model: order, document: document, errors: [] }
      attached = config.merge("bcc" => "audit@example.com", "attachmentsVariable" => "document")

      expect { @result = CodeGenerators::TestRunner.execute(described_class, config: attached, ctx: ctx) }
        .to change(Emails::Message, :count).by(1)

      message = Emails::Message.last
      expect(@result[:outcome]).to eq([message.id])
      expect(message.bcc).to eq("audit@example.com")
      expect(message.metadata["attachment_blob_ids"]).to eq([document["blob_id"]])
    end

    it "sends inside the configured locale" do
      create(:email_credential, mode: "sandbox")
      ctx = { customer_id: customer.id, model: order, errors: [] }
      seen = nil
      allow(I18n).to receive(:with_locale).and_wrap_original do |original, locale, &block|
        seen = locale
        original.call(locale, &block)
      end

      result = CodeGenerators::TestRunner.execute(described_class, config: config.merge("locale" => '"zh-CN"'), ctx: ctx)
      expect(result[:outcome]).to eq(ctx[:email_message_ids])
      expect(seen.to_s).to eq("zh-CN")
    end
  end
end
