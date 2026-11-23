# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ModuleHowtos#show", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/modules/authentication/howto" }

  before { enable_module!("authentication", customer) }

  it_behaves_like "an admin-guarded GET"

  it "places relevant new-tab links beside every step for each enabled module" do
    %w[email sms payment captcha ai_assistant website].each { |key| enable_module!(key, customer) }
    destinations = {
      "authentication" => %w[settings/modules/authentication/sign_up settings/modules/authentication/forget_password
                             modules/authentication/users modules/authentication/events],
      "email" => %w[settings/modules/emails/daily_cap modules/emails/templates modules/emails/lists
                    modules/emails/send_activities],
      "sms" => %w[settings/modules/sms/daily_cap modules/sms/campaigns modules/sms/contacts
                 modules/sms/messages],
      "payment" => %w[settings/modules/payments/merchant_accounts modules/payments/transactions
                      modules/payments/reconciliations],
      "captcha" => %w[settings/modules/captcha settings/modules/captcha domains domains],
      "ai_assistant" => %w[settings/modules/ai_assistant assistant assistant],
      "website" => %w[settings/modules/website modules/website settings/modules/website modules/website]
    }

    %w[authentication email sms payment captcha ai_assistant website].each do |key|
      get "/#{customer.id}/admin/modules/#{key}/howto"

      expect(response).to have_http_status(:ok)
      content = Nokogiri::HTML(response.body).at_css("main")
      rows = content.css("ol > li")
      steps = I18n.t("admin_modules.index.howto.steps.#{key}")
      expect(rows.size).to eq(destinations.fetch(key).size)
      expect(rows.map { |row| row.at_css("p").text.strip }).to eq(steps)
      rows.zip(destinations.fetch(key)).each do |row, path|
        anchors = row.css("a")
        expect(anchors.size).to eq(1), key
        link = anchors.first
        expect(link["href"]).to eq("/#{customer.id}/admin/#{path}"), key
        expect(link["target"]).to eq("_blank")
        expect(link["rel"].split).to contain_exactly("noopener", "noreferrer")
        expect(link.text).to include(I18n.t("admin_modules.index.howto.new_tab_hint"))
      end
      expect(content.css('a[href*="/admin/maintenance/"]')).to be_empty
      expect(content.css('a[href*="/admin/modules/"][href$="/howto"]')).to be_empty
      expect(Nokogiri::HTML(response.body).css("aside a[aria-current='page'][href$='/howto']").size).to be >= 1
    end
  end

  it "translates the guide and navigation for Chinese readers" do
    get guard_path, params: { locale: "zh-CN" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin_modules.index.howto.title", locale: :"zh-CN"))
    expect(response.body).to include(I18n.t("admin_modules.index.howto.steps.authentication", locale: :"zh-CN").first)
  end

  it "does not expose an unknown module" do
    get "/#{customer.id}/admin/modules/unknown/howto"
    expect(response).to have_http_status(:not_found)
  end

  it "does not expose unavailable modules or another customer's guide" do
    get "/#{customer.id}/admin/modules/email/howto"
    expect(response).to have_http_status(:not_found)

    other = create(:customer)
    get "/#{other.id}/admin/modules/authentication/howto"
    expect(response).not_to have_http_status(:ok)
  end
end
