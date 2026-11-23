# frozen_string_literal: true

require "rails_helper"

# BaseFieldComponent is abstract: its template (base_field_component.html.erb)
# calls `render_input`, which only concrete subclasses define. We exercise the
# shared wrapper/label/theme behaviour through a minimal stub subclass so this
# spec covers the base class and its template independently of any real field.
RSpec.describe FormFields::BaseFieldComponent, type: :component do
  # Named (not anonymous) so ViewComponent inherits the base sidecar template.
  stub_field = Class.new(described_class) do
    def self.name = "FormFields::StubFieldComponent"

    private

    def render_input
      tag.input(**input_attributes.merge(type: "text"))
    end
  end

  before { stub_const("FormFields::StubFieldComponent", stub_field) }

  def render_stub(**opts)
    render_inline(FormFields::StubFieldComponent.new(field_name: :email, **opts))
  end

  it "renders a wrapper div containing a label and the subclass input" do
    render_stub
    expect(rendered_content).to have_css("div > label")
    expect(rendered_content).to have_css("input[name='email'][type='text']")
  end

  it "wires the label's for attribute to the input id" do
    render_stub
    expect(rendered_content).to have_css("label[for='field_email']")
    expect(rendered_content).to have_css("input#field_email")
  end

  it "humanizes the field_name into the label by default" do
    render_inline(FormFields::StubFieldComponent.new(field_name: :first_name))
    expect(rendered_content).to have_css("label", text: "First name")
  end

  it "uses an explicit label when provided" do
    render_stub(label: "Your Email")
    expect(rendered_content).to have_css("label", text: "Your Email")
  end

  it "omits the required indicator when not required" do
    render_stub(required: false)
    expect(rendered_content).not_to have_css("label span.text-red-500")
    expect(rendered_content).not_to have_css("input[required]")
  end

  it "renders a red required indicator and required input when required" do
    render_stub(required: true)
    expect(rendered_content).to have_css("label span.text-red-500", text: "*")
    expect(rendered_content).to have_css("input[required]")
  end

  it "renders the placeholder and value on the input" do
    render_stub(placeholder: "you@example.com", value: "a@b.com")
    expect(rendered_content).to have_css("input[placeholder='you@example.com']")
    expect(rendered_content).to have_css("input[value='a@b.com']")
  end

  it "applies theme-resolved label classes" do
    render_stub(theme: { "label_style" => "uppercase" })
    expect(rendered_content).to have_css("label.uppercase")
  end

  it "applies theme-resolved input classes" do
    render_stub(theme: { "input_size" => "lg" })
    expect(rendered_content).to have_css("input.py-3")
  end

  it "merges arbitrary html attributes onto the input" do
    render_inline(FormFields::StubFieldComponent.new(field_name: :email, data: { role: "x" }))
    expect(rendered_content).to have_css("input[data-role='x']")
  end

  it "uses an explicit control ID for both label and input" do
    render_stub(id: "entry_email")
    expect(page).to have_css("label[for='entry_email']")
    expect(page).to have_css("input#entry_email")
  end

  it "lets an adapter compose label and chrome around only the input" do
    rendered = render_stub(input_only: true, id: "entry_email", class: "input-field", aria: { describedby: "entry_email_help" })
    expect(rendered.css("div, label")).to be_empty
    expect(rendered.at_css("input")["class"]).to eq("input-field")
    expect(rendered.at_css("input")["aria-describedby"]).to eq("entry_email_help")
  end
end
