# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Payments::RefundPaymentGenerator do
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

  it "is version 1.2.0" do
    expect(described_class._metadata[:version]).to eq("1.2.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:refund] = FlowchartRuntime::Payments.refund(
          ctx,
          payment: ctx[:payment_id],
          amount: BigDecimal("1.00"),
          reason: "duplicate"
        )
      end
    RUBY
  end

  it "omits amount and emits full mode without leaking a hidden amount" do
    expect(generated_step(described_class.sample_input.merge("refundMode" => "full", "amount" => "9.00"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:refund] = FlowchartRuntime::Payments.refund(
          ctx,
          payment: ctx[:payment_id],
          mode: "full",
          reason: "duplicate"
        )
      end
    RUBY
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:payment) do
      create(:payment, customer: customer, status: "succeeded", amount: 5.00, provider: "alipay", flow: "qr")
    end

    it "refunds a payment of the run tenant and rejects another tenant's payment" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})
      Current.customer = customer
      foreign = create(:payment, customer: other, status: "succeeded", amount: 5.00)
      ctx_a = { customer_id: customer.id, payment_id: payment.id, errors: [] }
      ctx_b = { customer_id: customer.id, payment_id: foreign.id, errors: [] }

      result = execute(described_class.sample_input, ctx_a)
      expect(result[:outcome]).to be_a(Payments::Refund)
      expect(ctx_a[:refund]).to eq(result[:outcome])
      expect(Payments::Refund.where(payment_id: payment.id)).to exist

      rejected = execute(described_class.sample_input, ctx_b)
      expect(rejected[:outcome]).to be(false)
      expect(ctx_b[:errors]).to eq([I18n.t("flowchart_runtime.errors.refund_payment.not_found")])
      expect(Payments::Refund.where(payment_id: foreign.id)).to be_empty
    end

    it "refunds the captured amount when refundMode is full" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})
      Current.customer = customer
      ctx = { customer_id: customer.id, payment_id: payment.id, errors: [] }

      result = execute(described_class.sample_input.merge("refundMode" => "full"), ctx)
      expect(result[:outcome]).to be_a(Payments::Refund)
      expect(result[:outcome].amount).to eq(payment.amount)
    end
  end
end
