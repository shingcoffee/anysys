# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::CustomerSignupMailer do
  let(:email) { "founder@acme.test" }
  let(:token) { "signup-token-fixture" }
  let(:mail) { described_class.instructions(email, token) }
  let(:confirm_path) { "/auth/sign_up/confirm?token=#{token}" }

  it "is addressed to the recipient" do
    expect(mail.to).to eq([email])
    expect(mail.from).to eq(["noreply@anysys.com"])
    expect(mail.subject).to eq(I18n.t("auth.mailer.customer_signup.subject"))
    expect(mail.subject).to eq("Confirm your Anysys account")
  end

  it "renders a multipart message with HTML and plain text" do
    expect(mail.html_part).to be_present
    expect(mail.text_part).to be_present
  end

  it "includes the confirm URL and copy in the HTML part" do
    html = mail.html_part.body.to_s

    expect(html).to include(I18n.t("auth.mailer.customer_signup.greeting", email: email))
    expect(html).to include(I18n.t("auth.mailer.customer_signup.instructions"))
    expect(html).to include(I18n.t("auth.mailer.customer_signup.action"))
    expect(html).to include(confirm_path)
    expect(html).to include(I18n.t("auth.mailer.customer_signup.fallback"))
  end

  it "includes the confirm URL and copy in the text part" do
    text = mail.text_part.body.to_s

    expect(text).to include(I18n.t("auth.mailer.customer_signup.greeting", email: email))
    expect(text).to include(confirm_path)
    expect(text).to include(I18n.t("auth.mailer.customer_signup.ignore"))
  end

  it "enqueues instead of delivering inline" do
    expect {
      described_class.instructions(email, token).deliver_later
    }.to have_enqueued_mail(described_class, :instructions)

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
