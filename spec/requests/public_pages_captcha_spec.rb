# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page captcha throttle", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:entity)  { create(:entity, :with_name_status_schema, customer: customer) }

  let(:page) do
    p = build(:page, :for_member, :for_public, customer: customer, entity: entity)
    p.launched = true
    config = JSON.parse(p.configuration)
    config["pages"] = [
      {
        "id" => "page_1",
        "name" => "Page 1",
        "fields" => [
          { "id" => "field_1", "property_slug" => "name", "property_type" => "text",
            "html_type" => "text", "label" => "Name", "width" => "full" }
        ]
      }
    ]
    p.configuration = config.to_json
    p.save!(validate: false)
    p.update_column(:flowchart_id, Flowcharts::DefaultPageFlowchart.fetch.id)
    p
  end

  it "does not embed a captcha widget on the public page" do
    get "/#{customer.id}/page/#{page.public_uuid}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("captcha-aliyun")
  end

  it "accepts a submit under the default throttle without a captcha token" do
    expect do
      post "/#{customer.id}/page/#{page.public_uuid}", params: { entity: { name: "hi" } }
    end.to change(EntityEntry, :count).by(1)
  end

  it "challenges when the page is set to every hit" do
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings, enabled: true)
    Captcha::UrlThrottle.create!(
      match_kind: "exact",
      url_pattern: "/#{customer.id}/page/#{page.public_uuid}",
      page: page,
      customer_id: customer.id,
      every_hit: true
    )
    Captcha::ThrottleRegistry.bust!

    get "/#{customer.id}/page/#{page.public_uuid}"
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/captcha/challenge")
  end

  it "does not mint a skip-grant when the vendor is unreachable on a fail-open page" do
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings, enabled: true)
    Captcha::UrlThrottle.create!(
      match_kind: "exact",
      url_pattern: "/#{customer.id}/page/#{page.public_uuid}",
      page: page,
      customer_id: customer.id,
      every_hit: true
    )
    Captcha::ThrottleRegistry.bust!
    expect(Captcha::ProviderSettings.active).to be_present
    path = "/#{customer.id}/page/#{page.public_uuid}"
    get path
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/captcha/challenge")

    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      Captcha::Activities::Verify::Result.new(outcome: :unreachable)
    )

    post "/captcha/challenge", params: {
      return_to: "/#{customer.id}/page/#{page.public_uuid}",
      captcha_verify_param: "dummy"
    }

    expect(response).to redirect_to("/#{customer.id}/page/#{page.public_uuid}")
    # The first exact GET is the one-use outage continuation. The configured
    # provider remains active; later hits must challenge again without a Grant.
    get "/#{customer.id}/page/#{page.public_uuid}"
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Captcha-Result"]).to eq("false")
    expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: path)).to be(false)
    get "/#{customer.id}/page/#{page.public_uuid}"
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/captcha/challenge")
  end

  it "bypasses an every-hit rule while the provider is unconfigured" do
    Captcha::Providers::Aliyun
    settings = create(:captcha_provider_settings, enabled: true)
    settings.write_config(prefix: nil)
    settings.save!
    path = "/#{customer.id}/page/#{page.public_uuid}"
    create(:captcha_url_throttle, match_kind: "exact", url_pattern: path, page: page,
                                 customer_id: customer.id, every_hit: true)
    Captcha::ThrottleRegistry.bust!
    expect(Captcha::ProviderSettings.active).to be_nil
    expect(Captcha::Activities::Verify).not_to receive(:call)
    get path
    expect(response).to have_http_status(:ok)
    expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: path)).to be(false)
  end
end
