# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::HelpEmails", type: :request do
  include_context "as admin"
  let(:guard_path) { admin_help_emails_path(customer.id) }

  it "sends mail to help@anysys.com" do
    post guard_path,
         params: { help_email: { subject: "Need a module", body: "Please turn on Payments." } }

    expect(response).to have_http_status(:redirect)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "help@anysys.com" ])
    expect(mail.reply_to).to eq([ admin.email ])
    expect(mail.body.encoded).to include("Please turn on Payments.")
  end

  it_behaves_like "an admin-guarded request", :post

  it "denies a member without sending mail" do
    sign_in create(:user, :member, customer: customer)
    post guard_path,
         params: { help_email: { subject: "Need a module", body: "Please turn on Payments." } }

    expect(response).not_to have_http_status(:ok)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
