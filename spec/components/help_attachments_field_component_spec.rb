# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpAttachmentsFieldComponent, type: :component do
  it "renders a dropzone with the file input name and hint" do
    render_inline(
      described_class.new(
        name: "support_ticket[images][]",
        accept: "image/png",
        hint: "JPEG only",
        label: "Screenshots",
        input_id: "help-notify-files"
      )
    )

    expect(page).to have_text("Screenshots")
    expect(page).to have_text("JPEG only")
    expect(page).to have_css("input[name='support_ticket[images][]'][accept='image/png'][multiple]")
    expect(page).to have_css("[data-help-attachments-target='input']")
    expect(page).to have_css("[data-help-attachments-target='list']")
    expect(page).to have_css("label[aria-labelledby='help-notify-files-label']")
  end

  it "uses compact padding for the reply dropzone" do
    render_inline(
      described_class.new(
        name: "support_ticket_message[images][]",
        accept: "image/png",
        hint: "JPEG only",
        input_id: "help-reply-files",
        compact: true
      )
    )

    expect(page).to have_css("label.py-2")
    expect(page).not_to have_css("label.py-6")
  end
end
