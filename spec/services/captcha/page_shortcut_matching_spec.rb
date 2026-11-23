# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Captcha matching for page shortcuts" do
  let_it_be(:customer) { create(:customer, id: 81721200) }
  let_it_be(:other_customer) { create(:customer, id: 12345678) }
  let(:page) { create(:page, :for_member, :for_public, customer: customer, launched: true) }
  let(:canonical) { "/#{customer.id}/page/#{page.public_uuid}" }
  let!(:shortcut) { PageShortcut.create!(customer_id: customer.id, path: "/join", target: page) }

  before do
    CustomDomainRecord.create!(hostname: "dedicated.example.test", customer_id: other_customer.id)
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings)
    Current.reset
  end
  after { Current.reset }

  def request(path = "/join", host: "shared.example.test", method: "GET", mount: "", params: {})
    env = Rack::MockRequest.env_for("http://#{host}#{path}", method: method, params: params)
    env["SCRIPT_NAME"] = mount
    env["REQUEST_URI"] = "#{mount}#{env.fetch('PATH_INFO')}#{env['QUERY_STRING'].present? ? "?#{env['QUERY_STRING']}" : ''}"
    env["REMOTE_ADDR"] = "1.2.3.4"
    env["rack.session"] = {}
    ActionDispatch::Request.new(env)
  end

  def throttle(path = canonical, **attrs)
    row = create(:captcha_url_throttle, match_kind: "exact", url_pattern: path, every_hit: true, **attrs)
    Captcha::ThrottleRegistry.bust!
    row
  end

  def call_gate(req)
    Captcha::RackGate.new(->(_env) { [200, { "Content-Type" => "text/plain" }, ["ok"]] }).call(req.env)
  end

  it "uses the canonical rule for GET/HEAD/POST without changing path, mount, identity parameters or Current" do
    throttle
    Current.customer = other_customer
    %w[GET HEAD POST].each do |method|
      req = request("/join?customer_id=12345678&uuid=forged", method: method, mount: "/anysys")
      req.path_parameters = { customer_id: "12345678", uuid: "forged" }
      before = [req.path_info, req.script_name, req.query_string, req.path_parameters.dup]
      rule = Captcha::UrlMatcher.for_request(req)
      expect(rule).to have_attributes(pattern: canonical, every_hit: true)
      expect(call_gate(req)[0]).to eq(302)
      expect([req.path_info, req.script_name, req.query_string, req.path_parameters]).to eq(before)
      expect(req.env[PageShortcuts::RouteConstraint::MATCH_KEY]).to be_nil
      expect(Current.customer).to eq(other_customer)
    end
  end

  it "shares canonical counters and grants across different aliases and the original endpoint" do
    throttle(every_hit: false, limit_count: 2, period_seconds: 60)
    PageShortcut.create!(customer_id: customer.id, path: "/register", target: page)
    expect(["/join", "/register", canonical].map { |path| call_gate(request(path))[0] }).to eq([200, 200, 302])
    Captcha::Grant.store(ip: "1.2.3.4", pattern: canonical, ttl: 60)
    expect(call_gate(request("/join"))[0]).to eq(200)
    expect(call_gate(request("/register"))[0]).to eq(200)
    expect(call_gate(request(canonical))[0]).to eq(200)
  end

  it "honors a canonical skipped rule and cannot bypass a protected page with a skipped alias rule" do
    row = throttle(skipped: true)
    expect(call_gate(request)[0]).to eq(200)
    row.update!(skipped: false)
    throttle("/join", skipped: true)
    expect(call_gate(request)[0]).to eq(302)
    expect(Captcha::UrlMatcher.for_request(request).pattern).to eq(canonical)
  end

  it "uses the public-page default rule when no custom canonical rule exists" do
    rule = Captcha::UrlMatcher.for_request(request)
    expect(rule).to have_attributes(pattern: canonical, limit_count: 100, period_seconds: 300, every_hit: false)
  end

  it "isolates two tenants with the same alias using the request host or explicit prefix, not query/body fields" do
    other_page = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    PageShortcut.create!(customer_id: other_customer.id, path: "/join", target: other_page)
    other_path = "/#{other_customer.id}/page/#{other_page.public_uuid}"
    throttle
    throttle(other_path, skipped: true)
    spoof = { "customer_id" => customer.id, "uuid" => page.public_uuid }
    req = request("/join?customer_id=#{customer.id}&uuid=#{page.public_uuid}", host: "dedicated.example.test", method: "POST", params: spoof)
    expect(Captcha::UrlMatcher.for_request(req).pattern).to eq(other_path)
    expect(call_gate(req)[0]).to eq(200)
    prefixed = request("/#{customer.id}/join", host: "dedicated.example.test", method: "POST", params: spoof)
    expect(Captcha::UrlMatcher.for_request(prefixed).pattern).to eq(canonical)
    expect(call_gate(prefixed)[0]).to eq(302)
  end

  it "applies a shared Page template rule to both tenants' mapped root paths" do
    shared = create(:page, :shared, :for_member, :for_public, launched: true)
    [customer, other_customer].each { |tenant| PageShortcut.create!(customer_id: tenant.id, path: "/", target: shared) }
    template = "/:customer_id/page/#{shared.public_uuid}"
    throttle(template, match_kind: "template")
    [request("/"), request("/12345678", method: "POST"), request("/", host: "dedicated.example.test", method: "HEAD")].each do |req|
      expect(Captcha::UrlMatcher.for_request(req).pattern).to eq(template)
      expect(call_gate(req)[0]).to eq(302)
    end
  end

  it "matches canonical website throttles for eligible reads, not website POSTs or offline sites" do
    feature_module = FeatureModules::Module.find_by!(key: "website")
    feature_module.update!(status: :active)
    create(:customer_feature_module, customer: customer, feature_module: feature_module)
    site = create(:website, :published, customer: customer)
    inner = create(:website_page, :published, website: site, slug: "pricing")
    PageShortcut.create!(customer_id: customer.id, path: "/offer", target: inner)
    path = "/#{customer.id}/site/pricing"
    throttle(path)
    %w[GET HEAD].each do |method|
      expect(Captcha::UrlMatcher.for_request(request("/offer", method: method)).pattern).to eq(path)
      expect(call_gate(request("/pricing", method: method))[0]).to eq(302)
    end
    expect(Captcha::UrlMatcher.for_request(request("/offer", method: "POST"))).to be_nil
    site.update!(published: false)
    expect(Captcha::UrlMatcher.for_request(request("/offer"))).to be_nil
  end

  it "does not borrow a canonical rule from an unavailable or foreign public Page" do
    throttle
    [{ launched: false }, { launched: true, audience_public: false },
     { audience_public: true, status: :inactive }].each do |attrs|
      page.update!(attrs)
      expect(Captcha::UrlMatcher.for_request(request(method: "POST"))).to be_nil
    end
    foreign = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    shortcut.update!(target: foreign)
    throttle("/#{other_customer.id}/page/#{foreign.public_uuid}")
    expect(Captcha::UrlMatcher.for_request(request)).to be_nil
  end

  it "preserves disabled-provider fail-open and the replay bypass" do
    throttle
    Captcha::ProviderSettings.delete_all
    expect(call_gate(request)[0]).to eq(200)
    req = request(method: "POST")
    req.env["captcha.replay"] = true
    expect(Captcha::UrlMatcher).not_to receive(:for_request)
    expect(call_gate(req)[0]).to eq(200)
  end

  it "keeps the original mounted alias, query and body in the challenge and one-time snapshot" do
    throttle
    req = request("/join?locale=zh-CN&tag=a&tag=b", method: "POST", mount: "/anysys",
                  params: { "name" => "Alice", "customer_id" => "12345678", "uuid" => "forged" })
    status, headers, = call_gate(req)
    expect(status).to eq(302)
    expect(URI.parse(headers.fetch("Location")).path).to eq("/anysys/captcha/challenge")
    expect(Array(headers.fetch("set-cookie")).join).to include("path=/anysys/captcha/challenge")
    return_to = Rack::Utils.parse_query(URI.parse(headers.fetch("Location")).query).fetch("return_to")
    expect(return_to).to eq("/anysys/join?locale=zh-CN&tag=a&tag=b")
    token = Rack::Utils.parse_cookies_header(Array(headers.fetch("set-cookie")).join(";"))[Captcha::RequestSnapshot::COOKIE]
    payload = Captcha::RequestSnapshot.take!(token, request: req, path: "/anysys/join")
    expect(payload).to include("path" => "/anysys/join", "path_info" => "/join", "script_name" => "/anysys",
                               "method" => "POST", "query" => "locale=zh-CN&tag=a&tag=b")
    expect(payload["params"]).to include("name" => "Alice", "customer_id" => "12345678", "uuid" => "forged")
    expect(Captcha::RequestSnapshot.take!(token, request: req, path: "/anysys/join")).to be_nil
  end

  it "keeps real dotted aliases distinct while formatted canonical routes share their throttle" do
    other_page = create(:page, :for_member, :for_public, customer: customer, launched: true)
    PageShortcut.create!(customer_id: customer.id, path: "/join.html", target: other_page)
    other_path = "/#{customer.id}/page/#{other_page.public_uuid}"
    throttle
    throttle(other_path, skipped: true)
    expect(Captcha::UrlMatcher.for_request(request("/join.html")).pattern).to eq(other_path)
    expect(call_gate(request("/join.html"))[0]).to eq(200)
    expect(Captcha::UrlMatcher.for_request(request("#{canonical}.json")).pattern).to eq(canonical)
    expect(call_gate(request("#{canonical}.json"))[0]).to eq(302)
  end

  it "validates challenge return_to aliases against the challenge host and mount while preserving the query" do
    other_page = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    PageShortcut.create!(customer_id: other_customer.id, path: "/join", target: other_page)
    other_path = "/#{other_customer.id}/page/#{other_page.public_uuid}"
    throttle(other_path)
    req = request("/captcha/challenge", host: "dedicated.example.test", method: "POST", mount: "/anysys")
    destination = "/anysys/join?customer_id=#{customer.id}&uuid=#{page.public_uuid}&tag=a&tag=b"
    expect(Captcha::ReturnTo.safe?(destination, request: req)).to be(true)
    expect(Captcha::ReturnTo.path_and_query(destination, request: req)).to eq(destination)
    expect(Captcha::UrlMatcher.for_path("/anysys/join", request: req).pattern).to eq(other_path)
    expect(req.path_info).to eq("/captcha/challenge")
    expect(req.script_name).to eq("/anysys")
    ["https://evil.test/join", "//evil.test/join", "/anysys/%6aoin", "/anysys/admin/join"].each do |path|
      expect(Captcha::ReturnTo.safe?(path, request: req)).to be(false)
    end
  end
end
