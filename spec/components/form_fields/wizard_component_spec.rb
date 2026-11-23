# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::WizardComponent, type: :component do
  let(:pages_config) do
    [
      { "id" => "page_1", "name" => "Step 1", "fields" => [] },
      { "id" => "page_2", "name" => "Step 2", "fields" => [] }
    ]
  end

  # Defaults to a two-page wizard posting to /submit; override any arg and
  # optionally pass a content block (forwarded as-is; nil when omitted).
  def render_wizard(**opts, &block)
    render_inline(described_class.new(**{ pages: pages_config, action: "/submit" }.merge(opts)), &block)
  end

  it "renders wizard container" do
    render_wizard
    expect(rendered_content).to have_css("[data-controller='wizard']")
  end

  it "renders progress indicator when show_progress is true" do
    render_wizard(show_progress: true)
    expect(rendered_content).to have_text("Step 1 of 2")
  end

  it "hides progress indicator when show_progress is false" do
    render_wizard(show_progress: false)
    expect(rendered_content).not_to have_text("Step 1 of 2")
  end

  it "renders previous and next buttons" do
    render_wizard
    expect(rendered_content).to have_button("Previous")
    expect(rendered_content).to have_button("Next")
  end

  it "renders submit button" do
    render_wizard(submit_text: "Finish")
    expect(rendered_content).to have_button("Finish")
  end

  it "uses slots for step content" do
    render_wizard do |wizard|
      wizard.with_step(id: "page_1") { "Step 1 content" }
      wizard.with_step(id: "page_2") { "Step 2 content" }
    end

    expect(rendered_content).to have_text("Step 1 content")
  end

  it "renders form with action" do
    render_wizard(action: "/my-action")
    expect(rendered_content).to have_css("form[action='/my-action']")
  end

  it "renders a valid submit button and multipart wizard form" do
    render_wizard
    expect(rendered_content).to have_css('form[enctype="multipart/form-data"]')
    expect(rendered_content).to have_css('button[type="submit"][data-wizard-target="submitButton"].hidden', visible: :all)
  end

  describe "captcha widget embedding" do
    it "does not embed a captcha widget on the wizard form" do
      render_wizard
      expect(rendered_content).not_to have_css("[data-controller='captcha-aliyun']")
      expect(rendered_content).not_to have_css("input[name='captcha_verify_param']")
    end
  end

  it "renders its content inside the form and toggles an extra action with the submit button" do
    render_wizard(extra_action: Journeys::RepeatButtonComponent.new(step: Journeys::Definition.new("steps" => [{ "key" => "r", "kind" => "relate", "repeat" => true }]).first_step)) { "<p data-role='intro'>Intro</p>".html_safe }

    expect(rendered_content).to have_css("form > p[data-role='intro']")
    expect(rendered_content).to have_css("span.hidden[data-wizard-target='submitButton'] button[name='_intent']", visible: :all)
  end

  it "renders no extra action by default" do
    render_wizard
    expect(rendered_content).to have_css("[data-wizard-target='submitButton']", count: 1, visible: :all)
  end
end
