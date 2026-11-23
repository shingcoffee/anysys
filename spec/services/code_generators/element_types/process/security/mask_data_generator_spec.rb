# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::MaskDataGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "card_number", "maskType" => "last4", "resultVar" => "masked" } }
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
        FlowchartRuntime::Step.attempt(ctx, :"mask_data.failed", FlowchartRuntime::Mask::Error) do
          ctx[:masked] = FlowchartRuntime::Mask.apply(ctx[:credit_card], type: "last4")
          true
        end
      end
    RUBY
  end

  it "generates last4 without default window kwargs" do
    expect(body).to include('FlowchartRuntime::Mask.apply(ctx[:card_number], type: "last4")')
  end

  describe "behaviour" do
    it "masks last4" do
      ctx = { card_number: "4111111111111234" }
      expect(execute(base, ctx)[:outcome]).to be_truthy
      expect(ctx[:masked]).to eq("************1234")
    end

    it "masks email" do
      ctx = { card_number: "ada@example.test" }
      execute(base.merge("maskType" => "email"), ctx)
      expect(ctx[:masked]).to eq("a**@example.test")
    end

    it "masks a display name" do
      ctx = { card_number: "Jane Doe" }
      execute(base.merge("maskType" => "name"), ctx)
      expect(ctx[:masked]).to eq("J*** D**")
    end

    it "masks an address while keeping the locality" do
      ctx = { card_number: "123 Main St, Springfield IL 62701" }
      execute(base.merge("maskType" => "address"), ctx)
      expect(ctx[:masked]).to eq("*** **** **, Springfield IL 62701")
    end

    it "masks a credit card through the PCI window" do
      ctx = { card_number: "4111-1111-1111-1234" }
      execute(base.merge("maskType" => "credit_card"), ctx)
      expect(ctx[:masked]).to eq("4111-11**-****-1234")
    end

    it "masks a Chinese mobile number first3+last4" do
      ctx = { card_number: "13812345678" }
      execute(base.merge("maskType" => "mobile"), ctx)
      expect(ctx[:masked]).to eq("138****5678")
    end

    it "masks a Chinese resident ID first6+last4" do
      ctx = { card_number: "110101199001011234" }
      execute(base.merge("maskType" => "id_number"), ctx)
      expect(ctx[:masked]).to eq("110101********1234")
    end
  end
end
