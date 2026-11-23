# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcut application-route precedence", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Route shadow sentinel",
                                              configuration: { form_settings: { modes: ["update"] } }.to_json)
    end
  end

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  after { Current.reset }

  def persisted_mapping(path, target = page)
    # Historical/imported rows can bypass the write contract. They still must
    # not bypass runtime path policy or the application's real route guards.
    PageShortcut.create!(customer_id: customer.id, path: path, target_type: target.class.name, target_id: target.id)
  end

  {
    "/up" => [:ok, "rails/health", "show"],
    "/oauth/userinfo" => [:unauthorized, "oauth/userinfo", "show"],
    "/auth/sign_in" => [:ok, "authentication/sessions", "new"],
    "/captcha/challenge" => [:not_found, "captcha/challenges", "show"]
  }.each do |path, (status, controller, action)|
    it "keeps GET/HEAD #{path} on its original endpoint despite a persisted public mapping" do
      persisted_mapping(path)
      %i[get head].each do |verb|
        public_send(verb, path)
        expect(response).to have_http_status(status)
        expect(request.path_parameters).to include(controller: controller, action: action)
        expect(response.body).not_to include(page.name)
        expect(response.body).to be_empty if verb == :head
      end
    end
  end

  %w[/admin/maintenance/page_shortcuts /member/profile].each do |relative|
    it "keeps anonymous GET/HEAD #{relative} behind tenant authentication despite a persisted public mapping" do
      persisted_mapping(relative)
      %i[get head].each do |verb|
        public_send(verb, "/#{customer.id}#{relative}")
        expect(response).to redirect_to(new_user_session_path)
        expect(request.path_parameters[:controller]).not_to eq("public_pages")
        expect(response.body).not_to include(page.name)
      end
    end
  end

  %w[/assets/shortcut-shadow /oauth/shortcut-shadow /sign-in /captcha/shortcut-shadow].each do |path|
    it "does not expose #{path} as an alias when there is no matching application endpoint" do
      persisted_mapping(path)
      [path, "/#{customer.id}#{path}"].each do |address|
        get address
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(page.name)
      end
    end
  end

  {
    "/robots.txt" => "text/plain",
    "/site-images/anysys/anysys-home-workspace-hero.svg" => "image/svg+xml"
  }.each do |path, content_type|
    it "keeps #{path} on the public file server despite a persisted mapping" do
      persisted_mapping(path)
      get path
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(content_type)
      expect(response.body).to eq(File.binread(Rails.root.join("public", path.delete_prefix("/"))))
      expect(response.body).not_to include(page.name)
      head path
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
    end
  end

  it "preserves canonical website home, reserved inner slug and media routes even with conflicting persisted mappings" do
    enable_module!("website", customer, name: "Website")
    site = create(:website, :published, customer: customer)
    home = create(:website_page, :home, :published, website: site, title: "Canonical protected home")
    inner = create(:website_page, :published, website: site, slug: "oauth", title: "Canonical reserved website page")
    %w[/site /site/oauth /site/media/invalid-signed-token].each { |relative| persisted_mapping(relative) }

    [[website_home_path(customer.id), home.title], [website_page_path(customer.id, inner.slug), inner.title]].each do |path, title|
      get path
      expect(response).to have_http_status(:ok)
      expect(request.path_parameters[:controller]).to eq("websites/pages")
      expect(response.body).to include(title)
      expect(response.body).not_to include(page.name)
      head path
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
    end
    get website_media_path(customer.id, "invalid-signed-token")
    expect(response).to have_http_status(:not_found)
    expect(request.path_parameters).to include(controller: "websites/assets", action: "show")
    expect(response.body).not_to include(page.name)
  end

  it "does not replace canonical Page UUID GET/POST identity with a persisted Page-namespace mapping" do
    canonical_page = Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Canonical UUID sentinel",
                                              configuration: { form_settings: { modes: ["update"] } }.to_json)
    end
    persisted_mapping("/page/#{canonical_page.public_uuid}")
    get public_page_path(customer.id, canonical_page.public_uuid)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(canonical_page.name)
    expect(response.body).not_to include(page.name)
    expect(request.path_parameters[:uuid]).to eq(canonical_page.public_uuid)

    # A page that only edits records still reaches its canonical submission
    # action and receives that action's 405, rather than selecting the shadow target.
    expect { post public_page_submit_path(customer.id, canonical_page.public_uuid) }.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:method_not_allowed)
    expect(request.path_parameters).to include(controller: "public_pages", action: "submit", uuid: canonical_page.public_uuid)
  end

  [
    ["member", %w[admin member]],
    ["admin", %w[admin]]
  ].each do |role, audiences|
    it "keeps a formerly public #{role} form's alias private even for an authorized canonical submitter" do
      persisted_mapping("/campaign/join")
      actor = create(:user, role.to_sym, customer: customer)
      sign_in actor
      # Devise's next-request sign-in is not committed by an unroutable 404.
      # Establish the session on a valid response before narrowing the page.
      get public_page_path(customer.id, page.public_uuid)
      expect(response).to have_http_status(:ok)
      Current.set(customer: customer) { page.update!(visible_audiences: audiences) }

      expect { post "/campaign/join" }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:not_found)
      expect { post public_page_submit_path(customer.id, page.public_uuid) }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:method_not_allowed)
      expect(request.path_parameters).to include(controller: "public_pages", action: "submit")
      get "/campaign/join"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "rejects POST to explicit website aliases including root without executing a public form" do
    enable_module!("website", customer, name: "Website")
    site = create(:website, :published, customer: customer)
    home = create(:website_page, :home, :published, website: site)
    persisted_mapping("/", home)
    persisted_mapping("/campaign/welcome", home)
    ["/", "/#{customer.id}/", "/campaign/welcome", "/#{customer.id}/campaign/welcome"].each do |path|
      expect { post path }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
