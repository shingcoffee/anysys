# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpComposeDialogComponent, type: :component do
  def render_dialog(kind: :notify, action: "/1/admin/support_tickets")
    render_inline(described_class.new(kind: kind, action: action))
  end

  it "renders a named dialog with a multipart form and dropzone" do
    render_dialog
    expect(page).to have_css("[data-help-menu-target='notifyDialog']", visible: :all)
    expect(page).to have_css("[role='dialog'][aria-labelledby='help-notify-title']", visible: :all)
    expect(page).to have_css("form[action='/1/admin/support_tickets'][enctype='multipart/form-data']", visible: :all)
    expect(page).to have_field("support_ticket[subject]", visible: :all)
    expect(page).to have_field("support_ticket[body]", visible: :all)
    expect(page).to have_css("input[placeholder='What do you need help with?']", visible: :all)
    expect(page).to have_css("input[name='support_ticket[images][]']", visible: :all)
    expect(page).to have_css("[data-controller='help-attachments']", visible: :all)
  end

  it "renders the email compose fields for the email kind" do
    render_dialog(kind: :email, action: "/1/admin/help_emails")
    expect(page).to have_css("[data-help-menu-target='emailDialog']", visible: :all)
    expect(page).to have_field("help_email[subject]", visible: :all)
    expect(page).to have_css("input[name='help_email[attachments][]']", visible: :all)
    expect(page).to have_text("Sent to help@anysys.com")
  end
end
