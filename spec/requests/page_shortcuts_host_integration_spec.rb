# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcuts across shared and dedicated hosts", type: :request do
  let_it_be(:customer, reload: true) { create(:customer) }
  let_it_be(:dedicated_customer, reload: true) { create(:customer) }
  let!(:hostname) { CustomDomainRecord.create!(hostname: "tenant.example.test", customer_id: dedicated_customer.id) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  after { Current.reset }

  def published_site(tenant)
    enable_module!("website", tenant, name: "Website")
    site = create(:website, :published, customer: tenant, name: "Host brand #{tenant.id}")
    home = create(:website_page, :home, :published, website: site, title: "Host home #{tenant.id}")
    inner = create(:website_page, :published, website: site, slug: "plans", title: "Host plans #{tenant.id}")
    [home, inner]
  end

  def public_form(tenant)
    Current.set(customer: tenant) do
      # A content-only paragraph renders no form. Include an actual bound input
      # so the canonical form-action/mount assertions exercise a real form.
      entity = create(:entity, :with_name_status_schema, customer: tenant)
      create(:page, :for_member, :for_public, customer: tenant, entity: entity, launched: true, name: "Host form #{tenant.id}",
                     configuration: { metadata: {}, pages: [{ id: "page_1", fields: [
                       { id: "host-copy", field_type: "paragraph", property_type: "layout", content: "Public host form" },
                       { id: "host-name", property_slug: "name", property_type: "text", html_type: "text", label: "Name", width: "full" }
                    ] }] }.to_json)
    end
  end

  def map_page(target, tenant:, path:)
    PageShortcut.create!(customer_id: tenant.id, path: path, target_type: target.class.name, target_id: target.id)
  end

  it "uses created, renamed, reassigned and destroyed bindings on the very next request" do
    third_customer = create(:customer)
    destinations = [customer, dedicated_customer, third_customer].to_h do |tenant|
      home, inner = published_site(tenant)
      map_page(inner, tenant: tenant, path: "/offers/current")
      [tenant.id, [home, inner]]
    end
    expect_tenant = ->(host, tenant) do
      host! host
      home, inner = destinations.fetch(tenant.id)
      [["/", home], ["/plans", inner], ["/offers/current", inner]].each do |path, target|
        get path, params: { customer_id: destinations.keys.find { |id| id != tenant.id }, page_slug: "forged" }
        expect(response).to have_http_status(:ok), "#{host}#{path}"
        expect(response.body).to include(target.title)
        expect(request.path_parameters[:customer_id]).to eq(tenant.id)
        destinations.except(tenant.id).values.flatten.each do |foreign|
          expect(response.body).not_to include(foreign.title)
        end
      end
      head "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
      expect(request.path_parameters[:customer_id]).to eq(tenant.id)
    end

    expect_tenant.call("live.example.test", customer)
    binding = CustomDomainRecord.create!(hostname: "LIVE.Example.TEST.", customer_id: dedicated_customer.id)
    expect(binding.reload).to have_attributes(hostname: "live.example.test", customer_id: dedicated_customer.id)
    expect(dedicated_customer).to be_active
    expect_tenant.call("live.example.test", dedicated_customer)

    binding.update!(hostname: "RENAMED.Example.TEST.", customer_id: third_customer.id)
    expect(binding.reload).to have_attributes(hostname: "renamed.example.test", customer_id: third_customer.id)
    expect_tenant.call("live.example.test", customer)
    expect_tenant.call("renamed.example.test", third_customer)

    binding.update!(customer_id: dedicated_customer.id)
    expect_tenant.call("renamed.example.test", dedicated_customer)
    get "/#{third_customer.id}/offers/current", params: { customer_id: customer.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(destinations.fetch(third_customer.id).last.title)
    expect(request.path_parameters[:customer_id]).to eq(third_customer.id)

    binding.destroy!
    expect_tenant.call("renamed.example.test", customer)
  end

  it "keeps retained inactive bindings terminal for root and inner requests until restore or removal" do
    shared_home, shared_inner = published_site(customer)
    dedicated_home, dedicated_inner = published_site(dedicated_customer)
    map_page(shared_inner, tenant: customer, path: "/offers/current")
    map_page(dedicated_inner, tenant: dedicated_customer, path: "/offers/current")
    host! hostname.hostname
    get "/"
    expect(response.body).to include(dedicated_home.title)

    expect(dedicated_customer.soft_delete).to be(true)
    expect(hostname.reload.customer_id).to eq(dedicated_customer.id)
    ["/", "/plans", "/offers/current"].each do |path|
      %i[get head].each do |verb|
        public_send(verb, path, params: { customer_id: customer.id, page_slug: shared_inner.slug })
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(shared_home.title, shared_inner.title, dedicated_home.title, dedicated_inner.title)
        expect(response.body).to be_empty if verb == :head
      end
    end
    get "/#{customer.id}/plans"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(shared_inner.title)

    expect(dedicated_customer.restore).to be(true)
    get "/offers/current"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dedicated_inner.title)
    expect(hostname.reload.customer_id).to eq(dedicated_customer.id)

    expect(dedicated_customer.soft_delete).to be(true)
    hostname.destroy!
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(shared_home.title)
    expect(response.body).not_to include(dedicated_home.title)
  end

  it "falls back to the default after permanent customer deletion removes its binding" do
    shared_home, = published_site(customer)
    doomed = create(:customer)
    binding = CustomDomainRecord.create!(hostname: "deleted.example.test", customer_id: doomed.id)
    expect(doomed.soft_delete).to be(true)
    host! binding.hostname
    get "/"
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(shared_home.title)

    doomed.destroy!
    expect(Customer.unscoped.exists?(id: doomed.id)).to be(false)
    expect(CustomDomainRecord.exists?(id: binding.id)).to be(false)
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(shared_home.title)
    expect(request.path_parameters[:customer_id]).to eq(customer.id)
  end

  it "serves identical paths and canonical form actions through normalized spellings of the customer domain" do
    home, inner = published_site(dedicated_customer)
    foreign_home, = published_site(customer)
    page = public_form(dedicated_customer)
    map_page(page, tenant: dedicated_customer, path: "/campaign/join")
    expect(hostname.reload).to have_attributes(hostname: "tenant.example.test", customer_id: dedicated_customer.id)
    expect(dedicated_customer).to be_active

    [hostname.hostname, "TENANT.Example.TEST."].each do |host|
      host! host
      [["/", home.title], ["/plans", inner.title], ["/campaign/join", page.name]].each do |path, marker|
        get path, params: { customer_id: customer.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(marker)
        expect(response.body).not_to include(foreign_home.title)
        expect(request.path_parameters[:customer_id]).to eq(dedicated_customer.id)
      end
      actions = Nokogiri::HTML(response.body).css("main form[action]").map { |form| form["action"] }
      expect(actions).to include(public_page_submit_path(dedicated_customer.id, page.public_uuid))
    end
  end

  it "serves a dedicated tenant's own clean website and form URLs while retaining every shared-host mapping" do
    shared_home, shared_inner = published_site(customer)
    dedicated_home, dedicated_inner = published_site(dedicated_customer)
    shared_form = public_form(customer)
    dedicated_form = public_form(dedicated_customer)
    map_page(shared_form, tenant: customer, path: "/campaign/join")
    map_page(dedicated_form, tenant: dedicated_customer, path: "/campaign/join")
    map_page(shared_inner, tenant: customer, path: "/offers/current")
    map_page(dedicated_inner, tenant: dedicated_customer, path: "/offers/current")

    [
      ["shared.example.test", "", shared_home, shared_inner, shared_form],
      ["tenant.example.test", "", dedicated_home, dedicated_inner, dedicated_form],
      ["shared.example.test", "/#{dedicated_customer.id}", dedicated_home, dedicated_inner, dedicated_form],
      ["tenant.example.test", "/#{customer.id}", shared_home, shared_inner, shared_form],
      ["sub.tenant.example.test", "", shared_home, shared_inner, shared_form]
    ].each do |host, prefix, home, inner, form|
      host! host
      [["/", home.title], ["/plans", inner.title], ["/offers/current", inner.title],
       ["/campaign/join", form.name]].each do |relative, marker|
        get "#{prefix}#{relative}"
        expect(response).to have_http_status(:ok), "#{host}#{prefix}#{relative}"
        expect(response.body).to include(marker)
        expect(response.headers["Location"]).to be_nil
      end
    end
  end

  it "uses trusted dedicated-host root identity for a mounted form, its canonical action, locale and HEAD" do
    published_site(dedicated_customer)
    page = public_form(dedicated_customer)
    foreign = public_form(customer)
    map_page(page, tenant: dedicated_customer, path: "/")
    map_page(foreign, tenant: customer, path: "/")
    host! "tenant.example.test"
    spoof = { locale: "zh-CN", customer_id: customer.id, cid: customer.id,
              uuid: foreign.public_uuid, page_slug: "plans", controller: "home", action: "index" }
    mount = { "SCRIPT_NAME" => "/portal", "REQUEST_URI" => "/portal/?locale=zh-CN" }

    get "/", params: spoof, env: mount
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.name)
    expect(response.body).not_to include(foreign.name)
    expect(Nokogiri::HTML(response.body).at_css("html")["lang"]).to eq("zh-CN")
    expect(request.path_info).to eq("/")
    expect(request.script_name).to eq("/portal")
    expect(request.path_parameters).to include(controller: "public_pages", action: "show",
                                             customer_id: dedicated_customer.id, uuid: page.public_uuid)
    actions = Nokogiri::HTML(response.body).css("main form[action]").map { |form| form["action"] }
    expect(actions).to include("/portal/#{dedicated_customer.id}/page/#{page.public_uuid}")

    expect { head "/", params: spoof, env: mount }.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
    expect(request.path_parameters).to include(controller: "public_pages", customer_id: dedicated_customer.id)

    # Rails URL helpers retain the preceding request's SCRIPT_NAME. This next
    # request intentionally exercises the unmounted canonical endpoint.
    get public_page_path(dedicated_customer.id, page.public_uuid, script_name: ""), params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.name)
  end

  it "opens the canonical captcha challenge for a mounted dedicated root alias without losing the original return URL" do
    page = public_form(dedicated_customer)
    foreign = public_form(customer)
    map_page(page, tenant: dedicated_customer, path: "/")
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings, enabled: true)
    Captcha::UrlThrottle.create!(match_kind: "exact", customer_id: dedicated_customer.id, page: page,
                                url_pattern: "/#{dedicated_customer.id}/page/#{page.public_uuid}", every_hit: true)
    Captcha::UrlThrottle.create!(match_kind: "exact", customer_id: customer.id, page: foreign,
                                url_pattern: "/#{customer.id}/page/#{foreign.public_uuid}", skipped: true)
    Captcha::ThrottleRegistry.bust!
    host! "tenant.example.test"
    query = Rack::Utils.build_query(locale: "zh-CN", customer_id: customer.id, uuid: foreign.public_uuid)
    original = "/portal/?#{query}"

    expect do
      get "/?#{query}", env: { "SCRIPT_NAME" => "/portal", "REQUEST_URI" => original }
    end.not_to change(EntityEntry, :count)
    expect(response).to have_http_status(:redirect)
    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq("/portal/captcha/challenge")
    expect(location.query_values.fetch("return_to")).to eq(original)

    # Simulate the proxy stripping SCRIPT_NAME on the next browser request.
    get location.path.delete_prefix("/portal"), params: location.query_values,
        env: { "SCRIPT_NAME" => "/portal", "REQUEST_URI" => location.request_uri }
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(controller: "captcha/challenges", action: "show")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('input[name="return_to"]')["value"]).to eq(original)
    expect(html.at_css('input[name="return_to"]').ancestors("form").first["action"]).to eq("/portal/captcha/challenge")
  end

  it "renders two shared Page override lines through host-selected and canonical URLs without leaking the preceding request" do
    shared = Current.set(customer: nil, shared_resources_mode: true) do
      create(:page, :shared, :for_member, :for_public, launched: true, configuration: {
        metadata: {}, pages: [{ id: "page_1", fields: [
          { id: "override-copy", field_type: "paragraph", property_type: "layout", content: "Global shared definition" }
        ] }]
      }.to_json)
    end
    global_head = shared.current_version_id
    markers = { customer => "Shared-host customer definition", dedicated_customer => "Dedicated-host customer definition" }
    markers.each do |tenant, marker|
      Current.set(customer: tenant, shared_resources_mode: false) do
        shared.reload
        config = JSON.parse(shared.configuration)
        config["pages"][0]["fields"][0]["content"] = marker
        shared.configuration = config.to_json
        shared.commit_version!
      end
      map_page(shared, tenant: tenant, path: "/campaign/shared-form")
    end
    heads = shared.page_customer_heads.order(:customer_id).pluck(:customer_id, :current_version_id)

    [
      ["tenant.example.test", "/campaign/shared-form", dedicated_customer],
      ["shared.example.test", "/campaign/shared-form", customer],
      ["tenant.example.test", "/#{customer.id}/campaign/shared-form", customer],
      ["shared.example.test", "/#{dedicated_customer.id}/campaign/shared-form", dedicated_customer],
      ["tenant.example.test", public_page_path(customer.id, shared.public_uuid), customer]
    ].each do |host, path, tenant|
      host! host
      other = tenant == customer ? dedicated_customer : customer
      get path, params: { customer_id: other.id, uuid: SecureRandom.uuid, locale: "zh-CN" },
                env: { "SCRIPT_NAME" => "/portal", "REQUEST_URI" => "/portal#{path}?locale=zh-CN" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(markers.fetch(tenant))
      expect(response.body).not_to include(markers.fetch(other), "Global shared definition")
      expect(request.params["customer_id"].to_i).to eq(tenant.id)
    end
    expect(shared.reload.current_version_id).to eq(global_head)
    expect(shared.page_customer_heads.order(:customer_id).pluck(:customer_id, :current_version_id)).to eq(heads)
  end
end
