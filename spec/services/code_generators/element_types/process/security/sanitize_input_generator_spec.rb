# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::SanitizeInputGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "user_input", "sanitizer" => "strip_tags", "resultVar" => "sanitized" } }
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
        FlowchartRuntime::Step.attempt(
          ctx,
          :"sanitize_input.failed",
          FlowchartRuntime::Sanitize::Error
        ) do
          ctx[:sanitized] = FlowchartRuntime::Sanitize.apply(ctx[:user_input], sanitizer: "strip_tags")
          true
        end
      end
    RUBY
  end

  it "emits rails tags and attributes only for the rails sanitizer" do
    config = described_class.sample_input.merge("sanitizer" => "rails", "allowedTags" => %w[b i],
                                               "allowedAttributes" => %w[href])
    src = generated_step(config)
    expect(src).to include("tags: [\"b\", \"i\"]")
    expect(src).to include("attributes: [\"href\"]")
    expect(generated_step).not_to include("tags:")
  end

  describe "behaviour" do
    it "strips tags" do
      ctx = { user_input: "<p>hello <b>world</b></p>" }
      expect(execute(base, ctx)[:outcome]).to be_truthy
      expect(ctx[:sanitized]).to eq("hello world")
    end

    it "escapes HTML" do
      ctx = { user_input: "<b>x</b>" }
      execute(base.merge("sanitizer" => "escape_html"), ctx)
      expect(ctx[:sanitized]).to include("&lt;b&gt;")
    end

    it "trims whitespace when flagged" do
      ctx = { user_input: "  hello  " }
      execute(base.merge("trimWhitespace" => true), ctx)
      expect(ctx[:sanitized]).to eq("hello")
    end

    it "fails when onOverflow is fail and the text exceeds maxLength" do
      ctx = { user_input: "hello world", errors: [] }
      result = execute(base.merge("maxLength" => 4, "onOverflow" => "fail"), ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors].first).to include("Could not sanitize")
    end

    it "removes null bytes when flagged" do
      ctx = { user_input: "ok\u0000bad" }
      execute(base.merge("removeNullBytes" => true), ctx)
      expect(ctx[:sanitized]).to eq("okbad")
    end
  end
end
