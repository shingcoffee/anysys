# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Outcome::HandOffToModuleGenerator do
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
        FlowchartRuntime::Handoff.request(
          ctx,
          module_key: "payment",
          input: {"amount" => ctx[:model].fee}
        )
      end
    RUBY
  end

  it "emits a distinct exit_target for each exitKind" do
    page = generate(described_class.sample_input.merge("exitKind" => "page", "exitPage" => 9))
    url = generate(described_class.sample_input.merge("exitKind" => "url", "exitUrl" => "https://ok.test"))
    route = generate(described_class.sample_input.merge("exitKind" => "route", "exitRoute" => "customer_home"))
    none = generate(described_class.sample_input.merge("exitKind" => "none"))

    expect([none, page, url, route].uniq.size).to eq(4)
    expect(page).to include('"kind" => "page"')
    expect(url).to include('"kind" => "url"')
    expect(route).to include('"kind" => "route"')
    expect(none).not_to include("exit_target:")
  end

  it "rejects a non-http exit URL" do
    codes = errors(described_class.sample_input.merge("exitKind" => "url", "exitUrl" => "javascript:alert(1)")).map(&:code)
    expect(codes).to include(:invalid_url)
  end

  it "drops unsafe, blank, unnamed and non-hash input rows" do
    src = generate(
      "moduleKey" => "payment",
      "input" => [
        { "key" => "amount", "value" => "ctx[:model].fee" },
        { "key" => "123bad", "value" => "ctx[:model].fee" },
        { "key" => "note", "value" => "" },
        { "key" => "evil", "value" => "foo; Kernel.exit" },
        { "key" => "commented", "value" => "ctx[:model].fee # injected" },
        "not-a-hash",
        { "key" => "ok", "value" => "ctx[:params][:note]" }
      ]
    )

    expect(src).to include('"amount" => ctx[:model].fee')
    expect(src).to include('"ok" => ctx[:params][:note]')
    expect(src).not_to include("123bad")
    expect(src).not_to include("Kernel.exit")
    expect(src).not_to include("injected")
    expect(src).not_to include('"note"')
    expect(src).not_to include('"evil"')
    expect(src).not_to include('"commented"')
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }

    it "parks an exit_target on the handoff for the run tenant" do
      enable_module!("demo_handoff", customer, name: "Demo").tap { |fm| fm.update!(handoff_enabled: true) }
      ctx = { customer_id: customer.id, errors: [] }
      result = execute(
        described_class.sample_input.merge(
          "moduleKey" => "demo_handoff",
          "input" => [],
          "exitKind" => "url",
          "exitUrl" => "https://ok.test"
        ),
        ctx
      )
      expect(result[:outcome]).to be(true)
      expect(ctx[:submission_outcome]["handoff"]).to include(
        "module_key" => "demo_handoff",
        "exit_target" => { "kind" => "url", "url" => "https://ok.test" }
      )
    end
  end
end
