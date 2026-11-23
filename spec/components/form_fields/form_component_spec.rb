# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::FormComponent, type: :component do
  # Renders the form with action "/submit" by default; yields "" as the body unless a block is given.
  def render_form(**opts)
    render_inline(described_class.new(action: "/submit", **opts)) do
      block_given? ? yield : ""
    end
  end

  it "renders form tag with content" do
    render_form(method: :post) { "<input type='text' name='field'>".html_safe }

    expect(rendered_content).to have_css("form[action='/submit']")
    expect(rendered_content).to have_css("form[method='post']")
    expect(rendered_content).to have_css("input[name='field']")
  end

  it "renders submit button with custom text" do
    render_form(submit_text: "Send Form")

    expect(rendered_content).to have_button("Send Form")
  end

  it "applies default submit text when not provided" do
    render_form

    expect(rendered_content).to have_button("Submit")
  end

  it "applies inline Tailwind classes to submit button" do
    render_form

    expect(rendered_content).to have_css("button.bg-indigo-600")
    expect(rendered_content).to have_css("button.text-white")
    expect(rendered_content).to have_css("button.rounded-lg")
  end

  it "renders CSRF token field" do
    render_form

    expect(rendered_content).to have_css("input[name='authenticity_token']", visible: :hidden)
  end

  it "uses multipart encoding so file inputs submit their bytes" do
    render_form
    expect(rendered_content).to have_css('form[enctype="multipart/form-data"]')
  end

  it "accepts custom css_class for form wrapper" do
    render_form(css_class: "my-custom-class")

    expect(rendered_content).to have_css("form.my-custom-class")
  end

  it "uses theme-driven field spacing" do
    render_form(theme: { "field_spacing" => "tight" })

    expect(rendered_content).to have_css("form.space-y-3")
  end

  it "uses default field spacing when no theme provided" do
    render_form

    expect(rendered_content).to have_css("form.space-y-5")
  end

  describe "captcha widget embedding" do
    it "does not embed a captcha widget on the form" do
      render_form
      expect(rendered_content).not_to have_css("[data-controller='captcha-aliyun']")
      expect(rendered_content).not_to have_css("input[name='captcha_verify_param']")
    end
  end

  it "applies themed button style" do
    render_form(theme: { "button_style" => "gradient", "primary_color" => "indigo" })

    expect(rendered_content).to have_css("button.bg-gradient-to-r")
  end

  it "applies themed button width" do
    render_form(theme: { "button_width" => "auto" })

    expect(rendered_content).to have_css("button.w-auto")
  end

  it "applies themed button size" do
    render_form(theme: { "button_size" => "lg" })

    expect(rendered_content).to have_css("button.py-3\\.5")
  end

  it "renders an extra action after the submit button" do
    render_inline(described_class.new(action: "/submit", extra_action: Journeys::RepeatButtonComponent.new(step: Journeys::Definition.new("steps" => [{ "key" => "r", "kind" => "relate", "repeat" => true }]).first_step)))

    expect(rendered_content).to have_css("button[type='submit'] + div button[name='_intent'][value='add_another']")
  end
end
