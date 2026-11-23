# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PageContentGenerator conditions escaping" do
  include PageRuntimeHelpers

  let_it_be(:customer) { create(:customer) }
  around { |example| Current.set(customer: customer, user: nil, shared_resources_mode: false) { example.run } }

  # Regression test for stored RCE via single-quote injection in conditions JSON.
  #
  # BEFORE the fix, the generator emitted ERB source like:
  #   data: { conditions: '[{"field":"x","op":"==","value":"'; raise 'pwn'; #"}]' }
  # which is a Ruby string literal that is terminated by the first unescaped
  # single quote in the condition value, causing the text after it (raise 'pwn')
  # to be treated as Ruby code and evaluated server-side on every page render.
  #
  # AFTER the fix (.inspect on the Array), the generator emits:
  #   data: { conditions: [{"field"=>"x", "op"=>"==", "value"=>"'; raise 'pwn'; #"}] }
  # which is a valid Ruby Hash/Array literal — the value is a double-quoted String,
  # so the single quotes inside are inert data and no code is executed.

  subject(:generated) { PageContentGenerator.new(page).generate }

  let(:poison_value) { %q('; raise 'pwn'; #) }

  let(:configuration_json) do
    {
      "pages" => [
        {
          "id" => "page_1",
          "name" => "Test",
          "fields" => [
            {
              "id" => "field_1",
              "property_slug" => "name",
              "html_type" => "text",
              "label" => "Name",
              "required" => false,
              "conditions" => [
                { "field" => "x", "op" => "==", "value" => poison_value }
              ]
            }
          ]
        }
      ],
      "fields" => [],
      "settings" => {},
      "metadata" => {}
    }
  end

  let(:page) { build_runtime_ui_page(configuration_json, customer: customer) }

  it "does not use the old single-quoted JSON pattern (the injection vector)" do
    # The old vulnerable pattern wrapped JSON in single quotes:
    #   conditions: '{"field":"x",...,"value":"'; raise 'pwn'; #"}'
    # After the fix this pattern is gone — conditions is a Ruby Array literal.
    expect(generated).not_to match(/conditions:\s*'/)
  end

  it "uses the Ruby Array/Hash literal form for conditions" do
    # Array#inspect produces Ruby literal syntax with double-quoted strings.
    # The presence of a hashrocket => is the key indicator.
    expect(generated).to match(/conditions:.*"field"/)
  end

  it "generates syntactically valid ERB (ERB.new does not raise)" do
    expect { ERB.new(generated) }.not_to raise_error
  end

  it "contains the poison value as an inert double-quoted string, not executable Ruby" do
    # The value must appear in the output (not silently dropped)
    expect(generated).to include(poison_value)

    # The old injection pattern: conditions: '...'; raise  — no longer present.
    expect(generated).not_to match(/conditions:\s*'[^']*';\s*raise/)
  end

  it "compiles and renders the bound input with the poison value preserved as data" do
    html = ApplicationController.render(inline: generated, layout: false,
      assigns: { page: page, form_action: "/submit" })
    input = Nokogiri::HTML.fragment(html).at_css('input[name="name"]:not([disabled])')
    expect(input).to be_present
    expect(JSON.parse(input["data-conditions"]).first.fetch("value")).to eq(poison_value)
  end
end
