# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntryActionsComponent, type: :component do
  def render_actions(**options)
    render_inline(described_class.new(submit_label: "Create Entry", submitting_label: "Creating…", **options))
  end

  it "renders the submit button with its pending label" do
    button = render_actions.at_css("button[type='submit']")

    expect(button.text.strip).to eq("Create Entry")
    expect(button["data-turbo-submits-with"]).to eq("Creating…")
    expect(button["disabled"]).to be_nil
  end

  it "links Cancel to the cancel path outside any frame" do
    link = render_actions(cancel_path: "/back").at_css("a")

    expect(link["href"]).to eq("/back")
    expect(link["data-turbo-frame"]).to eq("_top")
    expect(link.text.strip).to eq(I18n.t("common.actions.cancel"))
  end

  it "runs the dismiss action instead of linking when one is given" do
    rendered = render_actions(cancel_path: "/back", dismiss_action: "dialog#close")

    expect(rendered.css("a")).to be_empty
    expect(rendered.at_css("button[data-action='dialog#close']")).to be_present
  end

  it "leaves Cancel out without a path or action and can disable submit" do
    rendered = render_actions(disabled: true)

    expect(rendered.css("button").size).to eq(1)
    expect(rendered.at_css("button[type='submit']")["disabled"]).to be_present
  end

  it "renders an extra action right after the submit button" do
    rendered = render_actions(cancel_path: "/back", extra_action: Journeys::RepeatButtonComponent.new(step: Journeys::Definition.new("steps" => [{ "key" => "r", "kind" => "relate", "repeat" => true }]).first_step))

    expect(rendered.at_css("button[type='submit'] + button[name='_intent'][value='add_another']")).to be_present
  end
end
