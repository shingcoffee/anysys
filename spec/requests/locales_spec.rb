# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale switching", type: :request do
  let_it_be(:customer) { create(:customer) }

  it "sets the locale cookie and redirects back" do
    patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => "/somewhere" }
    expect(response).to redirect_to("/somewhere")
    expect(response.cookies["locale"]).to eq("zh-CN")
  end

  it "falls back to root when there is no referer" do
    patch "/locale", params: { locale: "zh-CN" }
    expect(response).to redirect_to(root_path)
  end

  it "ignores an unsupported locale but still redirects" do
    patch "/locale", params: { locale: "fr" }, headers: { "HTTP_REFERER" => "/x" }
    expect(response).to redirect_to("/x")
    expect(response.cookies["locale"]).to be_nil
  end

  ["/somewhere", "http://www.example.com/somewhere"].each do |referer|
    it "replaces the stale locale in #{referer} while retaining all other query values and the fragment" do
      query = "locale=en&q=account+%26+profile&tag=one&tag=two&filters%5Bstatus%5D=active&items%5B%5D=a&items%5B%5D=b&empty=&flag"
      patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => "#{referer}?#{query}#steps" }

      location = URI.parse(response.location)
      expect(location.path).to eq("/somewhere")
      expect(location.fragment).to eq("steps")
      expect(Rack::Utils.parse_query(location.query)).to eq(
        "locale" => "zh-CN", "q" => "account & profile", "tag" => %w[one two],
        "filters[status]" => "active", "items[]" => %w[a b], "empty" => "", "flag" => nil
      )
      expect(response.cookies["locale"]).to eq("zh-CN")
    end
  end

  it "replaces repeated and encoded locale keys with the supported choice" do
    patch "/locale", params: { locale: "en" }, headers: { "HTTP_REFERER" => "/x?locale=zh-CN&%6Cocale=unsupported&q=users" }

    expect(response).to redirect_to("/x?locale=en&q=users")
  end

  it "leaves a locale-free referer query and fragment unchanged" do
    patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => "/x?q=account%20profile&tag=one&tag=two#steps" }

    expect(response).to redirect_to("/x?q=account%20profile&tag=one&tag=two#steps")
  end

  it "does not replace an explicit referer locale with an unsupported choice" do
    patch "/locale", params: { locale: "fr" }, headers: { "HTTP_REFERER" => "/x?locale=en&q=account%20profile#steps" }

    expect(response).to redirect_to("/x?locale=en&q=account%20profile#steps")
    expect(response.cookies["locale"]).to be_nil
  end

  it "accepts the request's HTTPS origin and non-default port" do
    host! "locale.example.test:8443"
    https!
    patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => "https://locale.example.test:8443/x?locale=en" }

    expect(response).to redirect_to("https://locale.example.test:8443/x?locale=zh-CN")
  end

  [
    "https://external.example/x?locale=en",
    "//external.example/x?locale=en",
    "///external.example/x?locale=en",
    "https://www.example.com/x?locale=en",
    "http://www.example.com:8080/x?locale=en",
    "http://user@www.example.com/x?locale=en",
    "javascript:alert(1)",
    "http://[invalid",
    "/bad path?locale=en",
    "/x?locale=en&q=%ZZ",
    "relative/path?locale=en",
    ""
  ].each do |referer|
    it "falls back to root for unsafe or malformed referer #{referer.inspect}" do
      patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => referer }

      expect(response).to redirect_to(root_path)
      expect(response.cookies["locale"]).to eq("zh-CN")
    end
  end

  it "falls back to root for an unsupported choice with an external referer" do
    patch "/locale", params: { locale: "fr" }, headers: { "HTTP_REFERER" => "https://external.example/x?locale=en" }

    expect(response).to redirect_to(root_path)
    expect(response.cookies["locale"]).to be_nil
  end

  context "when signed in" do
    let(:user) { create(:user, customer: customer, role: :admin) }

    before { sign_in user }

    it "persists the choice to the user's profile" do
      expect {
        patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => "/x" }
      }.to change { user.reload.locale }.from(nil).to("zh-CN")
    end

    it "retains the saved preference and referer locale for an unsupported choice" do
      user.update!(locale: "zh-CN")

      expect {
        patch "/locale", params: { locale: "fr" }, headers: { "HTTP_REFERER" => "/x?locale=en&q=users#steps" }
      }.not_to change { user.reload.locale }
      expect(response).to redirect_to("/x?locale=en&q=users#steps")
      expect(response.cookies["locale"]).to be_nil
    end

    it "still switches locale while MFA verification is pending" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)

      expect {
        patch "/locale", params: { locale: "zh-CN" }, headers: { "HTTP_REFERER" => "/x" }
      }.to change { user.reload.locale }.from(nil).to("zh-CN")
      expect(response.cookies["locale"]).to eq("zh-CN")
    end
  end
end
