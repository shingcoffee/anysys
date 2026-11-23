# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Payments::RequestPaymentGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "is version 1.3.0" do
    expect(described_class._metadata[:version]).to eq("1.3.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Payments.request(
          ctx,
          amount: BigDecimal("10.00"),
          currency: "CNY",
          subject: "Registration fee",
          description: "Payer note"
        )
      end
    RUBY
  end

  it "emits description, metadata, expiry and exit_target when configured" do
    expect(generated_step(
      described_class.sample_input.merge(
        "description" => '"Note"',
        "metadata" => [{ "key" => "sku", "value" => '"abc"' }],
        "expiresInMinutes" => 15,
        "exitKind" => "url",
        "exitUrl" => "https://ok.test"
      )
    )).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Payments.request(
          ctx,
          amount: BigDecimal("10.00"),
          currency: "CNY",
          subject: "Registration fee",
          description: "Note",
          metadata: {"sku" => "abc"},
          expires_in_minutes: 15,
          exit_target: {"kind" => "url", "url" => "https://ok.test"}
        )
      end
    RUBY
  end

  it "rejects a non-http exit URL" do
    codes = errors(described_class.sample_input.merge("exitKind" => "url", "exitUrl" => "javascript:alert(1)")).map(&:code)
    expect(codes).to include(:invalid_url)
  end

  describe "updating the record paid for" do
    let(:paid_config) do
      described_class.sample_input.merge(
        "paidRecord" => "ctx[:parent]",
        "paidFields" => [{ "key" => "status", "value" => "Paid" }, { "key" => "", "value" => "skipped" }],
        "paidAtField" => "paid_on",
        "paymentReferenceField" => "payment_reference",
        "exitKind" => "record"
      )
    end

    it "emits the record, the fields set once paid, the stamp slots and a record exit" do
      expect(generated_step(paid_config)).to eq(<<~RUBY.chomp)
        def test_step(ctx, **)
          FlowchartRuntime::Payments.request(
            ctx,
            amount: BigDecimal("10.00"),
            currency: "CNY",
            subject: "Registration fee",
            description: "Payer note",
            paid_record: ctx[:parent],
            paid_fields: {"status" => "Paid"},
            paid_at_field: "paid_on",
            reference_field: "payment_reference",
            exit_target: {"kind" => "record"}
          )
        end
      RUBY
    end

    it "rejects a field name that is not an identifier" do
      config = described_class.sample_input.merge("paidFields" => [{ "key" => "paid status", "value" => "Paid" }], "paidAtField" => "1x")
      expect(errors(config).map { |error| [error.field.to_s, error.code] })
        .to include(["paidFields", :invalid_identifier], ["paidAtField", :invalid_identifier])
    end

    context "when paying for the page record of a known entity" do
      let(:entity) do
        build(:entity, property_schema: [
          { "name" => "Status", "name_slug" => "status", "type" => "String" },
          { "name" => "Paid on", "name_slug" => "paid_on", "type" => "String" },
          { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
        ].to_json)
      end
      let(:context) { { bound_entity: entity } }

      it "accepts its stored fields and refuses unknown or derived ones" do
        ok = described_class.sample_input.merge("paidFields" => [{ "key" => "status", "value" => "Paid" }], "paidAtField" => "paid_on")
        expect(errors(ok)).to eq([])

        bad = ok.merge("paidFields" => [{ "key" => "total", "value" => "1" }], "paymentReferenceField" => "missing")
        refused = errors(bad).select { |error| error.code == :not_a_field }
        expect(refused.map(&:field).map(&:to_s).uniq).to eq(["paidFields"])
        expect(refused.size).to eq(2)
      end

      it "does not check fields of another record" do
        config = described_class.sample_input.merge("paidRecord" => "ctx[:parent]", "paidFields" => [{ "key" => "missing", "value" => "x" }])
        expect(errors(config)).to eq([])
      end

      it "rejects a paidFields value that is not an option of that field" do
        choice = build(:entity, property_schema: [
          { "name" => "Status", "name_slug" => "status", "html_type" => "select",
            "config" => { "source" => "manual", "options" => [{ "label" => "Open", "value" => "Open" },
                                                              { "label" => "Paid", "value" => "Paid" }] } }
        ].to_json)
        gen = described_class.new({ "config" => {} }, { bound_entity: choice })
        ok = described_class.sample_input.merge("paidFields" => [{ "key" => "status", "value" => "Paid" }])
        expect(gen.validate_config(ok)).to eq([])

        bad = described_class.sample_input.merge("paidFields" => [{ "key" => "status", "value" => "Nope" }])
        refused = gen.validate_config(bad).select { |error| error.code == :invalid_option }
        expect(refused.map(&:field).map(&:to_s)).to eq(["paidFields"])
      end
    end

    it "rejects a currency that is not a 3-letter ISO code" do
      expect(errors(described_class.sample_input.merge("currency" => "renminbi")).map(&:code)).to include(:invalid_currency)
      expect(errors(described_class.sample_input.merge("currency" => "cny"))).to eq([])
    end
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    def enable!(cust)
      fm = enable_module!("payment", cust, name: "Payments")
      fm.update!(handoff_enabled: true)
    end

    it "parks a handoff only for a tenant with the Payment module enabled" do
      enable!(customer)
      ctx_a = { customer_id: customer.id, errors: [] }
      ctx_b = { customer_id: other.id, errors: [] }

      result = execute(described_class.sample_input.merge("amount" => 'BigDecimal("8.00")', "subject" => '"A"'), ctx_a)
      expect(result[:outcome]).to be(true)
      expect(ctx_a[:submission_outcome].dig("handoff", "input", "subject")).to eq("A")

      expect(execute(described_class.sample_input.merge("subject" => '"B"'), ctx_b)[:outcome]).to be(false)
      expect(ctx_b[:submission_outcome]).to be_nil
      expect(Payments::Order.count).to eq(0)
    end

    it "fails with a translated error when the module is disabled" do
      ctx = { customer_id: customer.id, errors: [] }
      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.request_payment.module_disabled")])
    end

    it "stamps description, metadata, expiry and an exit target onto the handoff" do
      enable!(customer)
      ctx = { customer_id: customer.id, errors: [] }
      expires_at = nil
      freeze_time do
        expires_at = 10.minutes.from_now.utc.iso8601
        execute(
          described_class.sample_input.merge(
            "description" => '"Note"',
            "metadata" => [{ "key" => "sku", "value" => '"abc"' }],
            "expiresInMinutes" => 10,
            "exitKind" => "route",
            "exitRoute" => "customer_home"
          ),
          ctx
        )
      end
      input = ctx[:submission_outcome].dig("handoff", "input")
      expect(input["body"]).to eq("Note")
      expect(input["metadata"]).to eq("sku" => "abc")
      expect(input["expires_at"]).to eq(expires_at)
      expect(ctx[:submission_outcome].dig("handoff", "exit_target")).to eq("kind" => "route", "name" => "customer_home")
    end

    context "with a saved record to mark paid" do
      let(:entity) do
        create(:entity, customer: customer, property_schema: [
          { "name" => "Status", "name_slug" => "status", "type" => "String" },
          { "name" => "Paid on", "name_slug" => "paid_on", "type" => "String" }
        ].to_json)
      end
      let(:entry) { create(:entity_entry, entity: entity, customer: customer, data: { "status" => "Open" }.to_json) }
      let(:config) do
        described_class.sample_input.merge(
          "paidFields" => [{ "key" => "status", "value" => "Paid" }],
          "paidAtField" => "paid_on",
          "exitKind" => "record"
        )
      end

      before { enable!(customer) }

      it "parks what to set once paid and an exit to the record, leaving the record unchanged" do
        ctx = { customer_id: customer.id, errors: [], model: entry }
        expect(execute(config, ctx)[:outcome]).to be(true)

        handoff = ctx[:submission_outcome]["handoff"]
        expect(handoff["on_success"]).to eq(
          "entity_id" => entity.id, "entry_id" => entry.id, "fields" => { "status" => "Paid" }, "paid_at_field" => "paid_on"
        )
        expect(handoff["exit_target"]).to eq("kind" => "record", "entity_id" => entity.id, "entry_id" => entry.id)
        expect(entry.reload.data_json["status"]).to eq("Open")
      end

      it "fails when the record is not saved" do
        ctx = { customer_id: customer.id, errors: [], model: EntityEntry.new(entity: entity, customer: customer) }
        expect(execute(config, ctx)[:outcome]).to be(false)
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.request_payment.invalid_paid_record")])
        expect(ctx[:submission_outcome]).to be_nil
      end

      it "fails when the record belongs to another tenant" do
        ctx = { customer_id: other.id, errors: [], model: entry }
        enable!(other)
        expect(execute(config, ctx)[:outcome]).to be(false)
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.request_payment.invalid_paid_record")])
      end

      it "fails on a field the payment cannot set" do
        ctx = { customer_id: customer.id, errors: [], model: entry }
        result = execute(config.merge("paymentReferenceField" => "missing"), ctx)
        expect(result[:outcome]).to be(false)
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.request_payment.invalid_paid_field", field_name: "missing")])
      end
    end
  end
end
