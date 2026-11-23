# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page shortcut routing", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let!(:hostname) { CustomDomainRecord.create!(hostname: "dedicated.example.test", customer_id: customer.id) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  def published_website(tenant = customer)
    enable_module!("website", tenant, name: "Website")
    site = create(:website, :published, customer: tenant, name: "Brand #{tenant.id}")
    home = create(:website_page, :home, :published, website: site, title: "Public home #{tenant.id}")
    inner = create(:website_page, :published, website: site, slug: "pricing", title: "Pricing #{tenant.id}")
    [site, home, inner]
  end

  def public_page(tenant = customer, **attributes)
    Current.set(customer: tenant) do
      create(:page, :for_member, :for_public, customer: tenant, launched: true, **attributes)
    end
  end

  def map_page(target, path: "/join", tenant: customer)
    PageShortcut.create!(customer_id: tenant.id, path: path, target_type: target.class.name, target_id: target.id)
  end

  def expect_not_routed(verb, path, **options)
    public_send(verb, path, **options)
    expect(response).to have_http_status(:not_found)
  end

  it "renders published root and automatic inner paths without changing PATH_INFO" do
    _site, _home, inner = published_website

    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Public home #{customer.id}")
    expect(request.path_info).to eq("/")

    get "/pricing"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(inner.title)
    expect(request.path_info).to eq("/pricing")
    expect(request.path_parameters).to include(controller: "websites/pages", action: "show")
  end

  it "keeps the named root helper and anonymous/signed-in Home fallback" do
    expect(root_path).to eq("/")
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in to your account")
    expect(request.path_parameters).to include(controller: "home", action: "index")

    actor = create(:user, :member, customer: customer)
    sign_in actor
    get "/"
    expect(response).to redirect_to(Authentication::LandingPath.for(actor))
  end

  it "falls back only for shared root; a tenant home without publication is 404" do
    site, = published_website
    site.update!(published: false)
    get "/"
    expect(request.path_parameters).to include(controller: "home", action: "index")
    ["/#{customer.id}", "/#{customer.id}/"].each { |path| expect_not_routed(:get, path) }
    expect_not_routed(:get, "/pricing")
  end

  it "selects customers using a dedicated host and an explicit prefix, never the session or query" do
    published_website
    published_website(other_customer)
    host! "dedicated.example.test"

    get "/pricing", params: { customer_id: other_customer.id, cid: other_customer.id, page_slug: "nonexistent" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pricing #{customer.id}")
    expect(response.body).not_to include("Pricing #{other_customer.id}")

    get "/#{other_customer.id}/pricing", params: { customer_id: customer.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pricing #{other_customer.id}")
  end

  it "overrides forged slug and tenant values before page lookup on a mounted alias" do
    _site, _home, inner = published_website
    map_page(inner, path: "/campaign/spring")

    get "/campaign/spring", params: { customer_id: other_customer.id, page_slug: "missing", uuid: SecureRandom.uuid },
                            env: { "SCRIPT_NAME" => "/anysys", "REQUEST_URI" => "/anysys/campaign/spring" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(inner.title)
    expect(request.path_info).to eq("/campaign/spring")
    expect(request.script_name).to eq("/anysys")
    expect(request.params).to include("customer_id" => customer.id, "page_slug" => inner.slug, "uuid" => nil)
  end

  it "dispatches home-target aliases to home and supports tenant-prefixed roots" do
    _site, home, = published_website
    map_page(home, path: "/welcome")
    ["/welcome", "/#{customer.id}/welcome", "/#{customer.id}", "/#{customer.id}/"].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(home.title)
      expect(request.path_parameters).to include(controller: "websites/pages", action: "home")
    end
  end

  it "resolves GET/HEAD for /12345678 and /12345678/ through the generic fallback glob" do
    prefixed_customer = create(:customer, id: 12345678)
    _site, home, = published_website(prefixed_customer)

    ["/12345678", "/12345678/"].each do |path|
      %i[get head].each do |verb|
        public_send(verb, path, params: { customer_id: customer.id, target_id: 0 })
        expect(response).to have_http_status(:ok)
        expect(request.path_parameters).to include(controller: "websites/pages", action: "home", customer_id: prefixed_customer.id)
        expect(response.body).to include(home.title) if verb == :get
        expect(response.body).to be_empty if verb == :head
      end
    end
  end

  it "renders nested public Page mappings with trusted UUID and preserves canonical GET" do
    page = public_page(name: "Trusted public form")
    map_page(page, path: "/campaign/join")
    forged = public_page(other_customer, name: "Foreign form")

    get "/campaign/join", params: { customer_id: other_customer.id, uuid: forged.public_uuid }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.name)
    expect(response.body).not_to include(forged.name)
    expect(request.params).to include("customer_id" => customer.id, "uuid" => page.public_uuid)

    get public_page_path(customer.id, page.public_uuid)
    expect(response).to have_http_status(:ok)
  end

  it "supports explicit public Page root mappings rather than falling through to Home" do
    page = public_page(name: "Root public page")
    map_page(page, path: "/")

    ["/", "/#{customer.id}", "/#{customer.id}/"].each do |path|
      %i[get head].each do |verb|
        public_send(verb, path)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(page.name) if verb == :get
        expect(response.body).to be_empty if verb == :head
        expect(request.path_parameters).to include(controller: "public_pages", action: "show")
      end
    end
  end

  it "isolates identical shortcut paths by the explicit URL customer" do
    page = public_page(name: "Tenant A form")
    foreign = public_page(other_customer, name: "Tenant B form")
    map_page(page)
    map_page(foreign, tenant: other_customer)

    get "/join"
    expect(response.body).to include(page.name)
    expect(response.body).not_to include(foreign.name)
    get "/#{other_customer.id}/join"
    expect(response.body).to include(foreign.name)
    expect(response.body).not_to include(page.name)
  end

  it "renders shared Pages from the selected customer's override line" do
    shared = create(:page, :shared, :for_member, :for_public, launched: true, configuration: {
      metadata: {}, theme: ThemeResolver::THEME_PRESETS["modern"].dup
    }.to_json)
    global_head = shared.current_version_id
    Current.set(customer: customer) do
      config = JSON.parse(shared.configuration)
      config["theme"] = ThemeResolver::THEME_PRESETS["showcase"].dup
      shared.configuration = config.to_json
      shared.commit_version!
    end
    map_page(shared)
    map_page(shared, tenant: other_customer)

    get "/join"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("from-violet-950")
    get "/#{other_customer.id}/join"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("from-slate-50")
    expect(response.body).not_to include("from-violet-950")
    expect(shared.reload.current_version_id).to eq(global_head)
  end

  it "rejects forged tenant or UUID parameters on the shared root public Page mapping" do
    page = public_page(name: "Trusted root form")
    foreign = public_page(other_customer, name: "Foreign root form")
    map_page(page, path: "/")
    get "/", params: { customer_id: other_customer.id, uuid: foreign.public_uuid }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.name)
    expect(response.body).not_to include(foreign.name)
  end

  it "allows a foreign authenticated admin to browse a mapped public website" do
    published_website
    actor = create(:user, :admin, customer: other_customer)
    sign_in actor

    get "/pricing"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Brand #{customer.id}")
    expect(request.path_parameters).to include(controller: "websites/pages", customer_id: customer.id)
    expect(EntityAttributeAudience.for_user(actor, customer_id: customer.id)).to eq("public")
  end

  it "allows foreign members as public viewers and retains the fixed owner exception" do
    page = public_page
    map_page(page)
    actor = create(:user, :member, customer: other_customer)
    sign_in actor
    get "/join"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.name)
    expect(EntityAttributeAudience.for_user(actor, customer_id: customer.id)).to eq("public")
    sign_out actor
    sign_in find_or_create_platform_owner
    get "/join"
    expect(response).to have_http_status(:ok)
  end

  it "rechecks publication and module enablement without leaking unavailable website content" do
    site, _home, inner = published_website
    map_page(inner, path: "/offer")
    inner.update!(published: false)
    expect_not_routed(:get, "/offer")
    expect_not_routed(:get, "/pricing")
    inner.update!(published: true)
    get "/offer"
    expect(response).to have_http_status(:ok)
    site.update!(published: false)
    expect_not_routed(:get, "/offer")
    site.update!(published: true)
    FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module: FeatureModules::Module.find_by!(key: "website")
    ).update!(status: :suspended)
    expect_not_routed(:get, "/offer")
  end

  it "fails closed when a public target is narrowed, unlaunched, inactive, missing or foreign" do
    page = public_page
    shortcut = map_page(page)
    [%w[admin member], %w[admin]].each do |audiences|
      page.update!(visible_audiences: audiences)
      expect_not_routed(:get, "/join")
      expect_not_routed(:post, "/join")
    end
    page.update!(visible_audiences: %w[admin member public], launched: false)
    expect_not_routed(:get, "/join")
    page.update!(launched: true, status: :inactive)
    expect_not_routed(:get, "/join")
    page.update!(status: :active)
    shortcut.update_columns(target_id: public_page(other_customer).id)
    expect_not_routed(:get, "/join")
    shortcut.update_columns(target_id: 0)
    expect_not_routed(:get, "/join")
  end

  it "supports HEAD with an empty body for both website and public Page aliases" do
    published_website
    map_page(public_page)
    ["/", "/pricing", "/join"].each do |path|
      head path
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
    end
  end

  it "does not turn format suffixes, reserved namespaces or unrelated HTTP verbs into aliases" do
    published_website
    page = public_page
    map_page(page)
    %w[/pricing.json /join.json /assets/join /auth/join /admin/join /member/join /page/join /rails/join].each do |path|
      expect_not_routed(:get, path)
    end
    %i[post patch put delete].each { |verb| expect_not_routed(verb, "/pricing") }
    %i[patch put delete].each { |verb| expect_not_routed(verb, "/join") }
    get "/up"
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(controller: "rails/health", action: "show")
  end

  it "never routes stale mappings under protected application namespaces as public pages" do
    page = public_page
    map_page(page)
    protected_paths = %w[/admin/maintenance/page_shortcuts /member/private-page /auth/private-page /site/unknown-page]
    protected_paths.each do |path|
      PageShortcut.create!(customer_id: customer.id, path: path, target_type: "Page", target_id: page.id)
    end
    get "/#{customer.id}/admin/maintenance/page_shortcuts"
    expect(response).to redirect_to(new_user_session_path)
    get "/#{customer.id}/member/private-page"
    expect(response).to redirect_to(new_user_session_path)
    expect(request.path_parameters).not_to include(controller: "public_pages")
    expect_not_routed(:get, "/auth/private-page")
    expect_not_routed(:get, "/#{customer.id}/site/unknown-page")
  end

  it "memoizes a resolved target once across all destination constraints" do
    map_page(public_page)
    allow(PageShortcuts::Resolver).to receive(:resolve).and_call_original
    get "/join"
    expect(response).to have_http_status(:ok)
    expect(PageShortcuts::Resolver).to have_received(:resolve).once
  end

  it "memoizes nil and never marks the Home fallback as a matched shortcut" do
    allow(PageShortcuts::Resolver).to receive(:resolve).and_call_original
    get "/"
    expect(request.path_parameters).to include(controller: "home", action: "index")
    expect(PageShortcuts::Resolver).to have_received(:resolve).once
    expect(request.env[PageShortcuts::RouteConstraint::MATCH_KEY]).to be_nil
  end

  context "public form submissions" do
    let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
    let(:page) do
      public_page(entity: entity, configuration: {
        metadata: { entity_id: entity.id, entity_name: entity.name },
        pages: [{ id: "page_1", name: "Form", fields: [
          { id: "name", property_slug: "name", property_type: "text", html_type: "text", label: "Name", width: "full" }
        ] }]
      }.to_json)
    end
    let!(:shortcut) { map_page(page) }

    it "keeps the rendered form action on the canonical submission endpoint" do
      get "/join"
      expect(response).to have_http_status(:ok)
      forms = Nokogiri::HTML(response.body).css("main form[action]")
      expect(forms.map { |form| form["action"] }).to include(public_page_submit_path(customer.id, page.public_uuid))
    end

    it "submits through the original action while overriding forged body identity and retaining locale" do
      expect do
        post "/join?locale=zh-CN", params: { name: "Alice", customer_id: other_customer.id,
                                            uuid: SecureRandom.uuid, page_slug: "pricing" }
      end.to change(EntityEntry, :count).by(1)
      expect(EntityEntry.last).to have_attributes(customer_id: customer.id, entity_id: entity.id)
      expect(response).to redirect_to("/join?locale=zh-CN")
      expect(request.path_parameters).to include(controller: "public_pages", action: "submit")
    end

    it "preserves canonical POST and redirects back to the preferred mapped public path" do
      expect { post public_page_submit_path(customer.id, page.public_uuid) }.to change(EntityEntry, :count).by(1)
      expect(response).to redirect_to("/join")
    end

    it "keeps a mount prefix and locale when canonical submission redirects to a mapped path" do
      expect do
        post "#{public_page_submit_path(customer.id, page.public_uuid)}?locale=zh-CN",
             env: { "SCRIPT_NAME" => "/anysys" }
      end.to change(EntityEntry, :count).by(1)
      expect(response).to redirect_to("/anysys/join?locale=zh-CN")
    end

    it "supports POST on a public Page root mapping" do
      shortcut.update!(path: "/")
      ["/", "/#{customer.id}", "/#{customer.id}/"].each do |path|
        expect { post path }.to change(EntityEntry, :count).by(1)
        expect(response).to redirect_to("/")
        expect(EntityEntry.last.customer_id).to eq(customer.id)
      end
    end

    it "accepts a foreign signed-in visitor with only the public field audience" do
      actor = create(:user, :member, customer: other_customer)
      entity.update!(property_schema: [
        { "name" => "Name", "name_slug" => "name" },
        { "name" => "Internal", "name_slug" => "internal", "visibility" => { "public" => false, "member" => true, "admin" => true } }
      ].to_json)
      sign_in actor
      expect { post "/join", params: { name: "Public visitor", internal: "Forged privileged value" } }.to change(EntityEntry, :count).by(1)
      expect(response).to redirect_to("/join")
      expect(EntityEntry.last).to have_attributes(customer_id: customer.id, entity_id: entity.id)
      expect(EntityEntry.last.data_json).to eq("name" => "Public visitor")
    end

    it "applies the existing canonical Page captcha rule to alias reads and submissions" do
      Captcha::Providers::Aliyun
      create(:captcha_provider_settings, enabled: true)
      Captcha::UrlThrottle.create!(match_kind: "exact", url_pattern: public_page_path(customer.id, page.public_uuid),
                                  page: page, customer_id: customer.id, every_hit: true)
      Captcha::ThrottleRegistry.bust!

      %i[get head post].each do |verb|
        expect { public_send(verb, "/join") }.not_to change(EntityEntry, :count)
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include("/captcha/challenge")
      end
    end

    it "retains Rails CSRF protection on alias submissions" do
      original = ActionController::Base.allow_forgery_protection
      original_show_exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
      ActionController::Base.allow_forgery_protection = true
      # Rails::Engine#build_request merges env_config over request-level env.
      Rails.application.env_config["action_dispatch.show_exceptions"] = :none
      expect do
        expect { post "/join" }
          .to raise_error(ActionController::InvalidAuthenticityToken)
      end.not_to change(EntityEntry, :count)
    ensure
      ActionController::Base.allow_forgery_protection = original
      Rails.application.env_config["action_dispatch.show_exceptions"] = original_show_exceptions
    end
  end
end
