# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise confirmation instructions" do
  let(:user) { create(:user) }
  let(:token) { "confirm-token-fixture" }
  let(:mail) { Devise::Mailer.confirmation_instructions(user, token) }
  let(:confirmation_path) { "/auth/confirmation?confirmation_token=#{token}" }

  it "is addressed to the user from the Devise sender" do
    expect(mail.to).to eq([user.email])
    expect(mail.from).to eq(["noreply@anysys.com"])
  end

  it "renders a multipart message with HTML and plain text" do
    expect(mail.html_part).to be_present
    expect(mail.text_part).to be_present
  end

  it "includes the confirmation URL and copy in the HTML part" do
    html = mail.html_part.body.to_s

    expect(html).to include(I18n.t("auth.mailer.confirmation.greeting", email: user.email))
    expect(html).to include(I18n.t("auth.mailer.confirmation.instructions"))
    expect(html).to include(I18n.t("auth.mailer.confirmation.action"))
    expect(html).to include(confirmation_path)
    expect(html).to include(I18n.t("auth.mailer.confirmation.fallback"))
  end

  it "includes the confirmation URL and copy in the text part" do
    text = mail.text_part.body.to_s

    expect(text).to include(I18n.t("auth.mailer.confirmation.greeting", email: user.email))
    expect(text).to include(confirmation_path)
    expect(text).to include(I18n.t("auth.mailer.confirmation.ignore"))
  end
end
