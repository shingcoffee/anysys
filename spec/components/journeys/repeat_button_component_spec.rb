# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::RepeatButtonComponent, type: :component do
  def step(repeat:)
    Journeys::Definition.new("steps" => [{ "key" => "relate_1", "kind" => "relate", "repeat" => repeat }]).first_step
  end

  it "renders a second submit button that asks to add another" do
    render_inline(described_class.new(step: step(repeat: true)))

    button = page.find("button[type='submit'][name='_intent'][value='add_another']")
    expect(button).to have_text(I18n.t("journeys.runtime.save_and_add_another"))
  end

  it "renders nothing for a step that doesn't repeat, or without a step" do
    expect(render_inline(described_class.new(step: step(repeat: false))).to_html).to be_blank
    expect(render_inline(described_class.new(step: nil)).to_html).to be_blank
  end

  it "offers itself to a form only for a repeatable step" do
    expect(described_class.for(step(repeat: true))).to be_a(described_class)
    expect(described_class.for(step(repeat: false))).to be_nil
    expect(described_class.for(nil)).to be_nil
  end
end
