# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::MailerShellComponent, type: :component do
  def render_shell(scope:, email: "reader@example.com", action_url: "https://anysys.test/go?token=abc")
    render_inline(described_class.new(scope: scope, email: email, action_url: action_url))
  end

  it "renders the confirmation copy and links the action URL twice" do
    render_shell(scope: :confirmation)

    expect(page).to have_text(I18n.t("auth.mailer.confirmation.heading"))
    expect(page).to have_text(I18n.t("auth.mailer.confirmation.title"))
    expect(page).to have_text(I18n.t("auth.mailer.confirmation.greeting", email: "reader@example.com"))
    expect(page).to have_text(I18n.t("auth.mailer.confirmation.instructions"))
    expect(page).to have_text(I18n.t("auth.mailer.confirmation.ignore"))
    expect(page).to have_text(I18n.t("auth.mailer.confirmation.footer"))
    expect(page).to have_css('a[href="https://anysys.test/go?token=abc"]', count: 2)
    expect(page).to have_link(I18n.t("auth.mailer.confirmation.action"))
  end

  it "renders the sign-in link copy from the same markup" do
    render_shell(scope: :sign_in_link)

    expect(page).to have_text(I18n.t("auth.mailer.sign_in_link.heading"))
    expect(page).to have_text(I18n.t("auth.mailer.sign_in_link.title"))
    expect(page).to have_text(I18n.t("auth.mailer.sign_in_link.greeting", email: "reader@example.com"))
    expect(page).to have_text(I18n.t("auth.mailer.sign_in_link.instructions"))
    expect(page).to have_link(I18n.t("auth.mailer.sign_in_link.action"))
  end

  it "renders reset-password copy including the note" do
    render_shell(scope: :reset_password)

    expect(page).to have_text(I18n.t("auth.mailer.reset_password.heading"))
    expect(page).to have_text(I18n.t("auth.mailer.reset_password.note"))
    expect(page).to have_link(I18n.t("auth.mailer.reset_password.action"))
  end

  it "renders the hidden preheader for inbox previews" do
    render_shell(scope: :sign_in_link)

    expect(page).to have_css("div[style*='mso-hide:all']",
                             text: I18n.t("auth.mailer.sign_in_link.preheader"),
                             visible: :all)
  end

  it "follows the requested locale" do
    I18n.with_locale(:"zh-CN") do
      render_shell(scope: :sign_in_link)

      expect(page).to have_text(I18n.t("auth.mailer.sign_in_link.action", locale: :"zh-CN"))
    end
  end

  it "keeps the auth scopes' copy key sets in step" do
    keys = described_class::COPY_KEYS + [:greeting]

    keys.each do |key|
      %w[confirmation sign_in_link reset_password customer_signup].each do |scope|
        expect(I18n.exists?("auth.mailer.#{scope}.#{key}", :en)).to be(true)
        expect(I18n.exists?("auth.mailer.#{scope}.#{key}", :"zh-CN")).to be(true)
      end
    end
  end
end
