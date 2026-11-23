# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::PlaygroundResultComponent, type: :component do
  let(:result) do
    { code: "def step(ctx, **)\n  ctx[:out] = ctx[:in]\nend", inputs: ["in"], outputs: ["out"], validation_errors: [] }
  end

  it "shows the step's inputs, outputs and generated code" do
    html = render_inline(described_class.new(result: result))

    expect(html.css("dl").text.squish).to include("Input ctx[:in]", "Output ctx[:out]")
    expect(html.text).to include("generated_step.rb", "ctx[:out] = ctx[:in]")
  end

  it "says when nothing was detected or generated" do
    html = render_inline(described_class.new(result: result.merge(code: nil, inputs: [], outputs: [])))

    expect(html.text).to include("none detected", "No code generated (nil)")
  end

  it "lists config validation errors instead of the code" do
    errors = [CodeGenerators::ConfigError.new(field: :in, code: :blank, message: "in is required"), "out is invalid"]
    html = render_inline(described_class.new(result: result.merge(validation_errors: errors)))

    expect(html.text).to include("The config was rejected")
    expect(html.css("li").map(&:text)).to eq(["in is required", "out is invalid"])
    expect(html.text).not_to include("generated_step.rb")
  end

  it "shows a request error as an alert" do
    html = render_inline(described_class.new(error: "unexpected token"))

    expect(html.text).to include("unexpected token")
    expect(html.text).not_to include("generated_step.rb")
  end
end
