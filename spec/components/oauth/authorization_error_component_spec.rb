# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::AuthorizationErrorComponent, type: :component do
  it "renders the I18n title and the error description" do
    render_inline(described_class.new(error_description: "The request is missing a required parameter."))

    expect(page).to have_text(I18n.t("oauth.authorize.error.title"))
    expect(page).to have_text("The request is missing a required parameter.")
  end
end
