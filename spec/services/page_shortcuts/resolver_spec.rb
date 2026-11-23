# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::Resolver do
  let_it_be(:customer) { create(:customer, id: 81721200) }
  let_it_be(:other_customer) { create(:customer, id: 12345678) }
  let(:website_module) { enable_module!("website", customer, name: "Website") }
  let!(:website) { create(:website, :published, customer: customer) }
  let!(:home) { create(:website_page, :published, :home, website: website) }
  let!(:pricing) { create(:website_page, :published, website: website, slug: "pricing") }
  let(:page) { create(:page, :for_member, :for_public, customer: customer, launched: true) }

  before do
    website_module
    enable_module!("website", other_customer, name: "Website")
    CustomDomainRecord.create!(hostname: "other.example.com", customer_id: other_customer.id)
    Current.reset
  end

  after { Current.reset }

  def request(path = "/", host: "shared.example.com", method: "GET", script_name: "")
    env = Rack::MockRequest.env_for("http://#{host}#{script_name}#{path}", method: method)
    env["PATH_INFO"] = path.split("?", 2).first
    env["SCRIPT_NAME"] = script_name
    env["REQUEST_URI"] = "#{script_name}#{path}"
    ActionDispatch::Request.new(env)
  end

  def shortcut(target, path:, customer_id: customer.id)
    PageShortcut.create!(customer_id: customer_id, path: path, target: target)
  end

  it "resolves automatic root, bare customer root, and inner slugs into immutable typed targets" do
    ["/", "/81721200", "/81721200/"].each do |path|
      target = described_class.resolve(request(path))
      expect(target).to have_attributes(customer_id: customer.id, target_type: "WebsitePage", target_id: home.id,
                                       controller: "websites/pages", action: "home", page_slug: nil, uuid: nil,
                                       canonical_path: "/81721200/site")
      expect(target).to be_frozen
      expect(target.canonical_path).to be_frozen
    end
    ["/pricing", "/pricing/", "/81721200/pricing"].each do |path|
      expect(described_class.resolve(request(path))).to have_attributes(target_id: pricing.id, action: "show",
                                                                        page_slug: "pricing", canonical_path: "/81721200/site/pricing")
    end
  end

  it "uses dedicated hosts for clean paths and explicit customer prefixes take precedence" do
    other_site = create(:website, :published, customer: other_customer)
    other_home = create(:website_page, :published, :home, website: other_site)
    other_pricing = create(:website_page, :published, website: other_site, slug: "pricing")

    expect(described_class.resolve(request("/", host: "other.example.com")).target_id).to eq(other_home.id)
    expect(described_class.resolve(request("/pricing", host: "other.example.com")).target_id).to eq(other_pricing.id)
    expect(described_class.resolve(request("/12345678/pricing")).target_id).to eq(other_pricing.id)
    expect(described_class.resolve(request("/81721200/pricing", host: "other.example.com")).target_id).to eq(pricing.id)
    expect(described_class.resolve(request("/pricing", host: "sub.other.example.com")).target_id).to eq(pricing.id)
  end

  it "round-trips a saved 255-byte nested alias on dedicated/prefixed hosts and mounts" do
    path = "/campaign/spring-#{'a' * 73}/launch-#{'b' * 73}/form-#{'c' * 78}"
    target = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    result = PageShortcuts::Activities::Save.call(shortcut: PageShortcut.new, customer_id: other_customer.id,
                                                params: { path: path, target: "Page:#{target.id}" })
    expect(result.success?).to be(true), result.errors.inspect
    expect(result.model.reload.path.bytesize).to eq(255)
    ["", "/portal"].each do |mount|
      [["other.example.com", path], ["shared.example.com", "/#{other_customer.id}#{path}"]].each do |host, address|
        %w[GET HEAD POST].each do |method|
          req = request(address, host: host, method: method, script_name: mount)
          before = [req.path_info, req.script_name]
          expect(described_class.resolve(req)).to have_attributes(customer_id: other_customer.id,
                                                                  target_id: target.id, uuid: target.public_uuid)
          expect([req.path_info, req.script_name]).to eq(before)
        end
      end
    end
  end

  it "does not loosen relative limits, raw spelling or namespaces when extracting a tenant prefix" do
    path = "/campaign/spring-#{'a' * 73}/launch-#{'b' * 73}/form-#{'c' * 78}"
    shared = create(:page, :shared, :for_member, :for_public, launched: true)
    shortcut(shared, path: path, customer_id: other_customer.id)
    ["/12345678#{path}d", "/12345678/#{path}", "//12345678#{path}",
     "/01234567#{path}", "/123456789#{path}", "/%31%32%33%34%35%36%37%38#{path}",
     "/12345678#{path}/../form", "/12345678/campaign/%2e%2e/form", "/12345678/campaign\\form"].each do |address|
      req = request
      req.path_info = address
      req.set_header("REQUEST_URI", address)
      expect(described_class.resolve(req)).to be_nil, address.inspect
    end
    req = request("/12345678#{path}", script_name: "/portal")
    req.set_header("REQUEST_URI", "/portal/12345678/#{path}")
    expect(described_class.resolve(req)).to be_nil
    %w[admin member auth assets rails page site].each do |namespace|
      shortcut(shared, path: "/#{namespace}/form", customer_id: other_customer.id)
      expect(described_class.resolve(request("/12345678/#{namespace}/form"))).to be_nil
    end
  end

  it "resolves arbitrary aliases to home, inner website pages, and launched public forms" do
    shortcut(home, path: "/campaign/welcome")
    shortcut(pricing, path: "/plans")
    shortcut(page, path: "/join")
    expect(described_class.resolve(request("/campaign/welcome"))).to have_attributes(target_id: home.id, action: "home")
    expect(described_class.resolve(request("/plans"))).to have_attributes(target_id: pricing.id, page_slug: "pricing")
    expect(described_class.resolve(request("/join"))).to have_attributes(target_id: page.id, controller: "public_pages",
                                                                       action: "show", uuid: page.public_uuid,
                                                                       canonical_path: "/81721200/page/#{page.public_uuid}")
  end

  it "allows an explicit form or inner website Page at root to override the automatic home" do
    mapping = shortcut(page, path: "/")
    expect(described_class.resolve(request)).to have_attributes(target_id: page.id, controller: "public_pages")
    mapping.update!(target: pricing)
    expect(described_class.resolve(request)).to have_attributes(target_id: pricing.id, action: "show", page_slug: "pricing")
  end

  it "scopes identical shared Page aliases to the requested tenant and does not read definitions" do
    shared = create(:page, :shared, :for_member, :for_public, launched: true)
    shortcut(shared, path: "/join")
    shortcut(shared, path: "/join", customer_id: other_customer.id)
    Current.customer = other_customer
    expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)

    expect(described_class.resolve(request("/join")).customer_id).to eq(customer.id)
    expect(described_class.resolve(request("/12345678/join")).customer_id).to eq(other_customer.id)
    expect(Current.customer).to eq(other_customer)
  end

  it "ignores forged query and route parameters, preserves mount paths, and rejects unrelated verbs" do
    shortcut(page, path: "/join")
    req = request("/join?customer_id=12345678&uuid=forged&page_slug=forged", script_name: "/mount", method: "HEAD")
    req.path_parameters = { customer_id: "12345678", uuid: "forged", page_slug: "forged" }
    original = [req.path_info, req.script_name, req.path_parameters.dup]
    expect(described_class.resolve(req)).to have_attributes(customer_id: customer.id, uuid: page.public_uuid)
    expect([req.path_info, req.script_name, req.path_parameters]).to eq(original)
    %w[PATCH PUT DELETE OPTIONS].each do |method|
      expect(described_class.resolve(request("/join", method: method))).to be_nil
    end
  end

  it "resolves POST only to eligible public Page aliases and keeps the show target for submit constraints" do
    shortcut(page, path: "/join")
    shortcut(page, path: "/")
    ["/", "/join", "/81721200", "/81721200/join"].each do |path|
      expect(described_class.resolve(request(path, method: "POST"))).to have_attributes(
        customer_id: customer.id, target_id: page.id, controller: "public_pages", action: "show",
        canonical_path: "/81721200/page/#{page.public_uuid}"
      )
    end
    shortcut(home, path: "/welcome")
    shortcut(pricing, path: "/plans")
    ["/welcome", "/plans", "/pricing", "/12345678"].each do |path|
      expect(described_class.resolve(request(path, method: "POST"))).to be_nil
    end
  end

  it "rechecks POST publication, visibility, tenant ownership and shared Page scope despite forged identity" do
    mapping = shortcut(page, path: "/join")
    req = request("/join?customer_id=12345678&uuid=forged", method: "POST")
    req.path_parameters = { customer_id: "12345678", uuid: "forged" }
    expect(described_class.resolve(req)).to have_attributes(customer_id: customer.id, target_id: page.id)
    [{ launched: false }, { launched: true, audience_public: false, audience_member: true },
     { audience_admin: true, audience_member: false, audience_public: false },
     { audience_public: true, status: :inactive }].each do |attributes|
      page.update!(attributes)
      expect(described_class.resolve(req)).to be_nil
    end
    foreign = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    mapping.update!(target: foreign)
    expect(described_class.resolve(req)).to be_nil
    shared = create(:page, :shared, :for_member, :for_public, launched: true)
    mapping.update!(target: shared)
    expect(described_class.resolve(req)).to have_attributes(customer_id: customer.id, target_id: shared.id)
    shortcut(shared, path: "/join", customer_id: other_customer.id)
    expect(described_class.resolve(request("/join", host: "other.example.com", method: "POST"))).to have_attributes(
      customer_id: other_customer.id, target_id: shared.id
    )
    mapping.update!(target_id: 999999999)
    expect(described_class.resolve(req)).to be_nil
    other_customer.update!(status: :inactive)
    expect(described_class.resolve(request("/join", host: "other.example.com", method: "POST"))).to be_nil
  end

  it "rechecks publication/enablement/deletion and never falls through from a stale root mapping" do
    mapping = shortcut(page, path: "/")
    req = request
    expect(described_class.resolve(req).target_id).to eq(page.id)
    page.update!(launched: false)
    expect(described_class.resolve(req)).to be_nil
    page.update!(launched: true, audience_public: false, audience_member: true)
    expect(described_class.resolve(req)).to be_nil
    page.update!(audience_public: true, status: :inactive)
    expect(described_class.resolve(req)).to be_nil
    page.update!(status: :active)
    expect(described_class.resolve(req).target_id).to eq(page.id)
    mapping.update!(target_id: 999999999)
    expect(described_class.resolve(req)).to be_nil
    mapping.destroy!
    expect(described_class.resolve(req).target_id).to eq(home.id)
    home.update!(published: false)
    expect(described_class.resolve(req)).to be_nil
    home.update!(published: true)
    website.update!(published: false)
    expect(described_class.resolve(req)).to be_nil
    website.update!(published: true)
    website_module.update!(status: :inactive)
    expect(described_class.resolve(req)).to be_nil
  end

  it "fails closed for legacy cross-tenant or automatic/explicit collisions except the same website target" do
    foreign = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    shortcut(foreign, path: "/foreign")
    expect(described_class.resolve(request("/foreign"))).to be_nil
    mapping = shortcut(page, path: "/pricing")
    expect(described_class.resolve(request("/pricing"))).to be_nil
    mapping.update!(target: pricing)
    expect(described_class.resolve(request("/pricing")).target_id).to eq(pricing.id)
  end

  it "rejects reserved/unsafe paths and unknown customers, even when Rails normalized the raw URI" do
    PageShortcuts::PathPolicy::RESERVED_SEGMENTS.each do |segment|
      shortcut(page, path: "/#{segment}")
      expect(described_class.resolve(request("/#{segment}"))).to be_nil
      expect(described_class.resolve(request("/81721200/#{segment}"))).to be_nil
    end
    ["/page/uuid", "/assets/app", "/rails/active_storage", "/.well-known/test", "/%70ricing",
     "/pricing.json", "/../pricing", "/pricing//", "/123456789/pricing", "/00000000/pricing",
     "/99999999/pricing", "/81721200/admin", "/pricing\\admin", "/pricing\n"].each do |path|
      req = request
      req.path_info = path
      req.set_header("REQUEST_URI", path)
      expect(described_class.resolve(req)).to be_nil, path.inspect
    end
    req = request("/pricing")
    req.set_header("REQUEST_URI", "//pricing")
    expect(described_class.resolve(req)).to be_nil
    req.set_header("REQUEST_URI", "/81721200//pricing")
    req.path_info = "/81721200/pricing"
    expect(described_class.resolve(req)).to be_nil
  end

  it "works as a native Journey request constraint without rewriting the request" do
    shortcut(page, path: "/join")
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw do
      get "/*shortcut_path", format: false,
          constraints: ->(req) { PageShortcuts::Resolver.resolve(req)&.controller == "public_pages" },
          to: ->(env) { [200, { "content-type" => "text/plain" }, [env.fetch("PATH_INFO")]] }
    end
    req = request("/join?uuid=forged", script_name: "/mount")
    response = routes.call(req.env)
    expect(response[0]).to eq(200)
    expect(response[2].each.to_a.join).to eq("/join")
    expect(req.script_name).to eq("/mount")
    expect(routes.call(request("/join", method: "POST").env)[0]).to eq(404)
    expect(routes.call(request("/81721200//join").env)[0]).to eq(404)
  end
end
