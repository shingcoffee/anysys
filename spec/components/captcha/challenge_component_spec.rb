# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::ChallengeComponent, type: :component do
  it "renders the continue form without putting a snapshot token in the page" do
    render_inline(described_class.new(
      return_to: "/auth/sign_in",
      configured: true,
      fail_closed: true
    ))

    expect(page).to have_text(I18n.t("captcha.challenge.title"))
    expect(page).to have_css("input[name=return_to][value='/auth/sign_in']", visible: :hidden)
    expect(page).not_to have_css("input[name=snapshot]")
  end
end
