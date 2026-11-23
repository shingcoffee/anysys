# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::StepActionsComponent, type: :component do
  def step(optional: false, repeat: false)
    Journeys::Definition::Step.new(key: "relate_1", kind: "relate", action_key: nil, label: nil, inputs: {},
                                   repeat: repeat, optional: optional, target: nil)
  end

  it "renders skip then repeat when the step is optional and repeats" do
    render_inline(described_class.new(step: step(optional: true, repeat: true)))

    buttons = page.all("button[type='submit'][name='_intent']")
    expect(buttons.map { |button| button[:value] }).to eq(%w[skip add_another])
    expect(page).to have_css("[class*='sm:flex-row']")
  end

  it "renders only skip for an optional step that does not repeat" do
    render_inline(described_class.new(step: step(optional: true)))

    expect(page).to have_css("button[value='skip']")
    expect(page).not_to have_css("button[value='add_another']")
  end

  it "renders only repeat for a repeating step that is not optional" do
    render_inline(described_class.new(step: step(repeat: true)))

    expect(page).to have_css("button[value='add_another']")
    expect(page).not_to have_css("button[value='skip']")
  end

  it "renders nothing without a skippable or repeating step" do
    expect(render_inline(described_class.new(step: step)).to_html).to be_blank
    expect(render_inline(described_class.new(step: nil)).to_html).to be_blank
  end

  it "offers itself only when the step repeats or is optional" do
    expect(described_class.for(step(optional: true))).to be_a(described_class)
    expect(described_class.for(step(repeat: true))).to be_a(described_class)
    expect(described_class.for(step)).to be_nil
    expect(described_class.for(nil)).to be_nil
  end
end
