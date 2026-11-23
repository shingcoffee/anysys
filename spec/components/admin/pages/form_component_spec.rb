# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::FormComponent, type: :component do
  it "posts a multipart form to the page action with the entry form's action bar" do
    rendered = render_inline(described_class.new(action: "/1/page/abc?return_to=admin_form", cancel_path: "/1/admin/pages")) do
      "<input name='entity[name]'>".html_safe
    end
    form = rendered.at_css("form")

    expect(form["action"]).to eq("/1/page/abc?return_to=admin_form")
    expect(form["method"]).to eq("post")
    expect(form["enctype"]).to eq("multipart/form-data")
    expect(form["data-turbo-frame"]).to eq("_top")
    expect(form.at_css("input[name='entity[name]']")).to be_present
    expect(form.at_css("button[type='submit']").text.strip).to eq(I18n.t("admin_misc.entities.entry_form.create"))
    expect(form.at_css("a[href='/1/admin/pages']")).to be_present
  end

  it "submits into the + Add New dialog's frame and cancels by closing the dialog" do
    rendered = render_inline(described_class.new(action: "/1/page/abc", cancel_path: "/1/admin/pages", frame: true))
    form = rendered.at_css("form")

    expect(form["data-turbo-frame"]).to be_nil
    expect(form.at_css("button[data-action='entity-quick-add-dialog#close']").text.strip).to eq(I18n.t("common.actions.cancel"))
    expect(form.css("a")).to be_empty
  end

  it "saves changes instead of carrying the page's create wording when it edits an entry" do
    rendered = render_inline(described_class.new(action: "/x", submit_text: "Enrol", update: true))
    button = rendered.at_css("button[type='submit']")

    expect(button.text.strip).to eq(I18n.t("admin_misc.entities.entry_form.update"))
    expect(rendered.to_html).to include(I18n.t("admin_misc.entities.entry_form.updating"))
  end

  it "uses the page's own submit text when it has one" do
    rendered = render_inline(described_class.new(action: "/x", submit_text: "Enrol"))

    expect(rendered.at_css("button[type='submit']").text.strip).to eq("Enrol")
    expect(rendered.css("a")).to be_empty
  end

  it "renders an extra action beside the submit button" do
    rendered = render_inline(described_class.new(action: "/1/page/abc", extra_action: Journeys::RepeatButtonComponent.new(step: Journeys::Definition.new("steps" => [{ "key" => "r", "kind" => "relate", "repeat" => true }]).first_step)))

    expect(rendered.css("button[type='submit']").map { |button| button["name"] }).to eq([nil, "_intent"])
  end
end
