# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModalDialogComponent, type: :component do
  it "renders a closed, labelled modal target with a close button around its content" do
    render_inline(described_class.new(id: "profile-dialog", title: "Create Student profile", description: "Lin Member")) { "Form body" }

    dialog = page.find("dialog#profile-dialog[data-modal-dialog-target='dialog']", visible: :all)
    expect(dialog[:open]).to be_nil
    expect(dialog["aria-labelledby"]).to eq("profile-dialog-title")
    expect(dialog["data-action"]).to eq("click->modal-dialog#backdrop")
    expect(dialog).to have_css("h2#profile-dialog-title", text: "Create Student profile", visible: :all)
    expect(dialog).to have_css("p", text: "Lin Member", visible: :all)
    close = dialog.find("button[data-action='modal-dialog#close']", visible: :all)
    expect(close["type"]).to eq("button")
    expect(close["aria-label"]).to eq(I18n.t("common.actions.close"))
    expect(dialog).to have_text("Form body")
  end

  it "omits the description line when none is given and escapes authored text" do
    render_inline(described_class.new(id: "d", title: "<script>x()</script>")) { "Body" }

    expect(page).to have_css("h2", text: "<script>x()</script>", visible: :all)
    expect(page).not_to have_css("script, header p", visible: :all)
  end

  it "defaults to the accent tile at the wide width" do
    render_inline(described_class.new(id: "d", title: "Form")) { "Body" }

    dialog = page.find("dialog", visible: :all)
    expect(dialog[:class]).to include("sm:max-w-3xl")
    expect(dialog).to have_css("span.bg-accent-subtle path[d='#{described_class::TONES[:accent][:icon]}']", visible: :all)
  end

  it "renders a narrow danger dialog for destructive confirmations" do
    render_inline(described_class.new(id: "d", title: "Delete", tone: :danger, width: :sm)) { "Body" }

    dialog = page.find("dialog", visible: :all)
    expect(dialog[:class]).to include("sm:max-w-lg")
    expect(dialog[:class]).not_to include("sm:max-w-3xl")
    expect(dialog).to have_css("span.bg-danger-subtle path[d='#{described_class::TONES[:danger][:icon]}']", visible: :all)
  end

  it "falls back to the defaults for an unknown tone or width" do
    render_inline(described_class.new(id: "d", title: "Odd", tone: :neon, width: :xl)) { "Body" }

    dialog = page.find("dialog", visible: :all)
    expect(dialog[:class]).to include("sm:max-w-3xl")
    expect(dialog).to have_css("span.bg-accent-subtle", visible: :all)
  end
end
