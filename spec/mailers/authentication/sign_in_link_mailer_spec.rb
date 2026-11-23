# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::SignInLinkMailer do
  let(:user) { create(:user) }
  let(:token) { "sign-in-token-fixture" }
  let(:mail) { described_class.sign_in_link(user, token) }

  it "is addressed to the user" do
    expect(mail.to).to eq([user.email])
    expect(mail.from).to eq(["noreply@anysys.com"])
    expect(mail.subject).to eq(I18n.t("auth.mailer.sign_in_link.subject"))
  end

  it "includes the sign-in URL in HTML and text" do
    expect(mail.html_part.body.to_s).to include("/auth/sign_in_link?token=#{token}")
    expect(mail.text_part.body.to_s).to include("/auth/sign_in_link?token=#{token}")
    expect(mail.html_part.body.to_s).to include(I18n.t("auth.mailer.sign_in_link.instructions"))
  end
end
