# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Captcha challenge and replay for page shortcuts", type: :request do
  let_it_be(:customer, reload: true) { create(:customer) }
  let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
  let(:page) do
    create(:page, :for_member, :for_public, customer: customer, entity: entity, launched: true, configuration: {
      metadata: { entity_id: entity.id, entity_name: entity.name },
      pages: [{ id: "page_1", name: "Form", fields: [
        { id: "name", property_slug: "name", property_type: "text", html_type: "text", label: "Name", width: "full" }
      ] }]
    }.to_json).tap { |created| created.update_column(:flowchart_id, Flowcharts::DefaultPageFlowchart.fetch.id) }
  end
  let!(:shortcut) { PageShortcut.create!(customer_id: customer.id, path: "/join", target: page) }
  let(:canonical) { public_page_path(customer.id, page.public_uuid) }
  let!(:hostname) { CustomDomainRecord.create!(hostname: "forms.example.test", customer_id: customer.id) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  before do
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings)
    create(:captcha_url_throttle, match_kind: "exact", url_pattern: canonical, page: page,
                                 customer_id: customer.id, every_hit: true)
    Captcha::ThrottleRegistry.bust!
    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      Captcha::Activities::Verify::Result.new(outcome: :success)
    )
  end

  def submission_form(tenant)
    Current.set(customer: tenant) do
      bound_entity = create(:entity, :with_name_status_schema, customer: tenant)
      configuration = JSON.parse(page.configuration)
      configuration["metadata"] = { entity_id: bound_entity.id, entity_name: bound_entity.name }
      create(:page, :for_member, :for_public, customer: tenant, entity: bound_entity, launched: true,
                    name: "Reassigned host form #{tenant.id}", configuration: configuration.to_json)
        .tap { |created| created.update_column(:flowchart_id, Flowcharts::DefaultPageFlowchart.fetch.id) }
    end
  end

  it "switches dedicated GET/HEAD/POST captcha scope immediately without accepting forged tenant identity" do
    other_customer = create(:customer)
    other_page = submission_form(other_customer)
    PageShortcut.create!(customer_id: other_customer.id, path: "/join", target: other_page)
    Captcha::UrlThrottle.find_by!(customer_id: customer.id, url_pattern: canonical).update!(skipped: true)
    create(:captcha_url_throttle, match_kind: "exact", customer_id: other_customer.id, page: other_page,
                                 url_pattern: public_page_path(other_customer.id, other_page.public_uuid), every_hit: true)
    Captcha::ThrottleRegistry.bust!
    host! hostname.hostname
    get "/join"
    expect(response).to have_http_status(:ok)

    hostname.update!(customer_id: other_customer.id)
    %i[get head post].each do |verb|
      expect do
        public_send(verb, "/join", params: { customer_id: customer.id, uuid: page.public_uuid, name: "Spoofed tenant" })
      end.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:redirect)
      expect(Addressable::URI.parse(response.location).path).to eq(captcha_challenge_path)
    end

    get "/#{customer.id}/join", params: { customer_id: other_customer.id, uuid: other_page.public_uuid }
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(customer_id: customer.id, uuid: page.public_uuid)
    expect(response.body).not_to include(other_page.name)
  end

  [false, true].each do |prefixed|
    it "re-resolves a captured #{prefixed ? 'explicit-customer' : 'unprefixed'} POST after a hostname reassignment" do
      other_customer = create(:customer)
      other_page = submission_form(other_customer)
      PageShortcut.create!(customer_id: other_customer.id, path: "/join", target: other_page)
      other_canonical = public_page_path(other_customer.id, other_page.public_uuid)
      create(:captcha_url_throttle, match_kind: "exact", customer_id: other_customer.id, page: other_page,
                                   url_pattern: other_canonical, every_hit: true)
      Captcha::ThrottleRegistry.bust!
      host! hostname.hostname
      path = prefixed ? "/#{customer.id}/join" : "/join"
      return_to = "#{path}?locale=zh-CN&customer_id=#{customer.id}&uuid=#{page.public_uuid}"
      expect do
        post return_to, params: { entity: { name: "Live hostname replay" }, customer_id: other_customer.id, uuid: other_page.public_uuid }
      end.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:redirect)
      expect(response.cookies[Captcha::RequestSnapshot::COOKIE]).to be_present

      hostname.update!(customer_id: other_customer.id)
      selected_page = prefixed ? page : other_page
      selected_canonical = prefixed ? canonical : other_canonical
      foreign_canonical = prefixed ? other_canonical : canonical
      get captcha_challenge_path, params: { return_to: return_to, customer_id: customer.id, uuid: page.public_uuid }
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('input[name="return_to"]')["value"]).to eq(return_to)
      expect do
        post captcha_challenge_path, params: { return_to: return_to, captcha_verify_param: "valid",
                                              customer_id: customer.id, uuid: page.public_uuid }
      end.to change(EntityEntry, :count).by(1)
      expect(EntityEntry.last).to have_attributes(customer_id: selected_page.customer_id, entity_id: selected_page.entity_id)
      expect(EntityEntry.last.data_json).to include("name" => "Live hostname replay")
      expect(response).to redirect_to("#{path}?locale=zh-CN")
      expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: selected_canonical)).to be(true)
      expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: foreign_canonical)).to be(false)

      get return_to
      expect(response).to have_http_status(:ok)
      expect(request.path_parameters).to include(customer_id: selected_page.customer_id, uuid: selected_page.public_uuid)
      expect do
        post captcha_challenge_path, params: { return_to: return_to, captcha_verify_param: "valid-again" }
      end.not_to change(EntityEntry, :count)
    end
  end

  it "does not replay a dedicated-host snapshot or grant another tenant when its retained customer becomes inactive" do
    host! hostname.hostname
    expect { post "/join", params: { name: "Unavailable tenant" } }.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:redirect)
    expect(customer.soft_delete).to be(true)
    expect(hostname.reload.customer_id).to eq(customer.id)
    expect do
      post captcha_challenge_path, params: { return_to: "/join", captcha_verify_param: "valid" }
    end.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:not_found)
    expect(Captcha::Activities::Verify).not_to have_received(:call)
    expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: canonical)).to be(false)
  end

  it "renders the alias challenge and grants the same canonical rule for subsequent reads" do
    host! "forms.example.test"
    get "/join?locale=zh-CN"
    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("captcha.challenge.title"))

    post captcha_challenge_path, params: { return_to: "/join?locale=zh-CN", captcha_verify_param: "valid" }
    expect(response).to redirect_to("/join?locale=zh-CN")
    get "/join"
    expect(response).to have_http_status(:ok)
    get canonical
    expect(response).to have_http_status(:ok)
  end

  it "routes a real dotted alias to its own target without borrowing the undotted alias's captcha policy" do
    dotted_page = create(:page, :for_member, :for_public, customer: customer, entity: entity, launched: true,
                                configuration: page.configuration)
                         .tap { |created| created.update_column(:flowchart_id, Flowcharts::DefaultPageFlowchart.fetch.id) }
    PageShortcut.create!(customer_id: customer.id, path: "/join.html", target: dotted_page)
    dotted_path = public_page_path(customer.id, dotted_page.public_uuid)
    create(:captcha_url_throttle, match_kind: "exact", url_pattern: dotted_path, page: dotted_page,
                                 customer_id: customer.id, every_hit: true, skipped: true)
    Captcha::ThrottleRegistry.bust!
    host! hostname.hostname

    %i[get head].each do |verb|
      public_send(verb, "/join.html")
      expect(response).to have_http_status(:ok)
      expect(request.path_parameters).to include(uuid: dotted_page.public_uuid)
    end
    expect { post "/join.html", params: { entity: { name: "Dotted alias submission" } } }.to change(EntityEntry, :count).by(1)
    get "/join"
    expect(response.location).to include("/captcha/challenge")

    dotted_page.update!(launched: false)
    get "/join.html"
    expect(response).to have_http_status(:not_found)
  end

  it "replays the original alias POST once with its locale and trusted identity despite forged body values" do
    host! "forms.example.test"
    expect do
      post "/join?locale=zh-CN", params: { entity: { name: "Alice" }, customer_id: "99999999", uuid: SecureRandom.uuid }
    end.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:redirect)
    expect(response.cookies[Captcha::RequestSnapshot::COOKIE]).to be_present

    expect do
      post captcha_challenge_path, params: { return_to: "/join?locale=zh-CN", captcha_verify_param: "valid" }
    end.to change(EntityEntry, :count).by(1)
    expect(EntityEntry.last).to have_attributes(customer_id: customer.id, entity_id: entity.id)
    expect(EntityEntry.last.data_json).to include("name" => "Alice")
    expect(response).to redirect_to("/join?locale=zh-CN")
    expect do
      post captcha_challenge_path, params: { return_to: "/join?locale=zh-CN", captcha_verify_param: "valid-again" }
    end.not_to change(EntityEntry, :count)
  end

  it "preserves the mount while challenging and replaying a Page root alias" do
    shortcut.update!(path: "/")
    env = { "SCRIPT_NAME" => "/anysys", "REQUEST_URI" => "/anysys/?locale=zh-CN" }
    expect { post "/?locale=zh-CN", params: { entity: { name: "Root form" } }, env: env }.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("return_to=%2Fanysys%2F%3Flocale%3Dzh-CN")
    expect do
      # Use the browser's external URL for cookie path matching; emulate the
      # mount/proxy's router-relative PATH_INFO independently.
      post "/anysys/captcha/challenge", params: { return_to: "/anysys/?locale=zh-CN", captcha_verify_param: "valid" },
           env: { "SCRIPT_NAME" => "/anysys", "PATH_INFO" => "/captcha/challenge", "REQUEST_URI" => "/anysys/captcha/challenge" }
    end.to change(EntityEntry, :count).by(1)
    expect(EntityEntry.last.data_json).to include("name" => "Root form")
    expect(response).to redirect_to("/anysys/?locale=zh-CN")
  end

  it "rejects a challenge when the mapped target goes offline before replay" do
    post "/join", params: { name: "Alice" }
    expect(response).to have_http_status(:redirect)
    page.update!(launched: false)
    expect do
      post captcha_challenge_path, params: { return_to: "/join", captcha_verify_param: "valid" }
    end.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:not_found)
    expect(Captcha::Activities::Verify).not_to have_received(:call)
  end

  describe "CSRF-enabled snapshot replay" do
    around do |example|
      previous = ActionController::Base.allow_forgery_protection
      previous_origin = ActionController::Base.forgery_protection_origin_check
      previous_per_form = ActionController::Base.per_form_csrf_tokens
      previous_exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
      ActionController::Base.allow_forgery_protection = true
      ActionController::Base.forgery_protection_origin_check = true
      ActionController::Base.per_form_csrf_tokens = true
      Rails.application.env_config["action_dispatch.show_exceptions"] = :none
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = previous
      ActionController::Base.forgery_protection_origin_check = previous_origin
      ActionController::Base.per_form_csrf_tokens = previous_per_form
      Rails.application.env_config["action_dispatch.show_exceptions"] = previous_exceptions
    end

    def token_from_form(body)
      Nokogiri::HTML(body).at_css('input[name="authenticity_token"]')["value"]
    end

    def original_form_token
      row = Captcha::UrlThrottle.find_by!(url_pattern: canonical)
      row.update!(skipped: true)
      Captcha::ThrottleRegistry.bust!
      get "/join"
      expect(response).to have_http_status(:ok)
      # Generated public-page forms currently use a global token. Mint a real
      # Rails per-form token for the alias to exercise path+method verification
      # rather than letting that global token mask a replay-context regression.
      origin = PublicPagesController.new
      origin.set_request!(request)
      origin.set_response!(ActionDispatch::Response.new)
      token = origin.send(:form_authenticity_token, form_options: { action: "/join", method: "post" })
      row.update!(skipped: false)
      Captcha::ThrottleRegistry.bust!
      token
    end

    it "proves the original per-form token before capture and replays it with a different challenge token" do
      original_token = original_form_token
      expect { post "/join", params: { entity: { name: "CSRF verified" }, authenticity_token: original_token } }.not_to change(EntityEntry, :count)
      expect(response.cookies[Captcha::RequestSnapshot::COOKIE]).to be_present
      get captcha_challenge_path, params: { return_to: "/join" }
      challenge_token = token_from_form(response.body)
      expect(challenge_token).not_to eq(original_token)
      expect do
        post captcha_challenge_path, params: { return_to: "/join", captcha_verify_param: "valid", authenticity_token: challenge_token }
      end.to change(EntityEntry, :count).by(1)
      expect(EntityEntry.last.data_json).to include("name" => "CSRF verified")
    end

    it "rejects missing and forged original tokens even though the challenge could issue its own token" do
      original_form_token
      [nil, "forged"].each do |token|
        expect do
          post "/join", params: { name: "Attack", authenticity_token: token }
        end.to raise_error(ActionController::InvalidAuthenticityToken)
        expect(EntityEntry.count).to eq(0)
      end
      expect(Captcha::Activities::Verify).not_to have_received(:call)
    end

    it "rejects the challenge's valid per-form token when presented to the original target" do
      get captcha_challenge_path, params: { return_to: "/join" }
      token = token_from_form(response.body)
      expect { post "/join", params: { authenticity_token: token, name: "Wrong form" } }
        .to raise_error(ActionController::InvalidAuthenticityToken)
      expect(EntityEntry.count).to eq(0)
    end

    it "rejects a foreign original Origin even with a valid token" do
      token = original_form_token
      expect { post "/join", params: { name: "Foreign origin", authenticity_token: token }, headers: { "Origin" => "https://evil.example" } }
        .to raise_error(ActionController::InvalidAuthenticityToken)
      expect(EntityEntry.count).to eq(0)
    end

    it "preserves a header-only original token and validates the challenge separately" do
      token = original_form_token
      post "/join", params: { entity: { name: "Header CSRF" } }, headers: { "X-CSRF-Token" => token }
      expect(response).to have_http_status(:redirect)
      get captcha_challenge_path, params: { return_to: "/join" }
      challenge_token = token_from_form(response.body)
      expect do
        post captcha_challenge_path, params: { return_to: "/join", captcha_verify_param: "valid", authenticity_token: challenge_token }
      end.to change(EntityEntry, :count).by(1)
    end

    it "does not replay a snapshot cookie transplanted into another same-IP browser session" do
      original_token = original_form_token
      post "/join", params: { name: "Session A", authenticity_token: original_token }
      snapshot = response.cookies.fetch(Captcha::RequestSnapshot::COOKIE)
      other = ActionDispatch::Integration::Session.new(Rails.application)
      other.host! request.host
      other.get captcha_challenge_path, params: { return_to: "/join" }
      other_token = token_from_form(other.response.body)
      other.cookies[Captcha::RequestSnapshot::COOKIE] = snapshot
      expect do
        other.post captcha_challenge_path, params: { return_to: "/join", captcha_verify_param: "valid", authenticity_token: other_token }
      end.not_to change(EntityEntry, :count)
      expect(other.response).to have_http_status(:redirect)
    end
  end
end
