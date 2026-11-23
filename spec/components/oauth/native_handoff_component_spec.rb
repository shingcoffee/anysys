# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::NativeHandoffComponent, type: :component do
  let(:redirect_uri) { "http://127.0.0.1:8765/callback?code=abc&state=xyz" }

  it "wires Stimulus to the loopback URL and offers a Turbo-free continue link" do
    render_inline(described_class.new(redirect_uri: redirect_uri))

    root = page.find("[data-controller='oauth-native-handoff']")
    expect(root["data-oauth-native-handoff-url-value"]).to eq(redirect_uri)
    expect(page).to have_text(I18n.t("oauth.authorize.handoff.title"))
    expect(page).to have_link(I18n.t("oauth.authorize.handoff.continue"), href: redirect_uri)
    expect(page).to have_css("a[href='#{redirect_uri}'][data-turbo='false']")
  end

  # The href carries the authorization code; without rel=noreferrer the browser
  # hands it to the loopback listener in the Referer header too.
  it "does not leak the authorization code through Referer" do
    render_inline(described_class.new(redirect_uri: redirect_uri))

    expect(page).to have_css("a[href='#{redirect_uri}'][rel='noreferrer']")
  end
end
