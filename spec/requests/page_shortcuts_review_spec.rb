# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcut root failures and public render scopes", type: :request do
  let_it_be(:customer, reload: true) { create(:customer) }
  let_it_be(:other_customer, reload: true) { create(:customer) }
  let(:page) { create(:page, :for_member, :for_public, customer: customer, launched: true) }
  let!(:hostname) { CustomDomainRecord.create!(hostname: "forms.example.test", customer_id: other_customer.id) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
    Current.reset
  end

  it "returns a terminal empty root 404 for unavailable explicit targets on either host despite forged parameters" do
    mine = PageShortcut.create!(customer_id: customer.id, path: "/", target: page)
    shared = create(:page, :shared, :for_member, :for_public, launched: false)
    PageShortcut.create!(customer_id: other_customer.id, path: "/", target: shared)
    mine.update!(target_id: 999999999)
    ["shared.example.test", "forms.example.test"].each do |host|
      host! host
      %i[get head].each do |verb|
        public_send(verb, "/", params: { customer_id: customer.id, uuid: page.public_uuid, controller: "home", action: "index" })
        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
        expect(request.path_parameters).to include(controller: "page_shortcuts/unavailable", action: "show")
      end
    end
    sign_in create(:user, :member, customer: customer)
    get "/"
    expect(response).to have_http_status(:not_found)
    expect(response.headers["Location"]).to be_nil
  end

  it "renders a saved maximum-length Page alias through dedicated and prefixed mounted URLs" do
    path = "/campaign/spring-#{'a' * 73}/launch-#{'b' * 73}/form-#{'c' * 78}"
    target = create(:page, :for_member, :for_public, customer: other_customer, launched: true, name: "Maximum-length public alias")
    result = PageShortcuts::Activities::Save.call(shortcut: PageShortcut.new, customer_id: other_customer.id,
                                                params: { path: path, target: "Page:#{target.id}" })
    expect(result.success?).to be(true), result.errors.inspect
    expect(result.model.reload.path.bytesize).to eq(255)
    ["", "/portal"].each do |mount|
      [["forms.example.test", path], ["shared.example.test", "/#{other_customer.id}#{path}"]].each do |host, address|
        host! host
        %i[get head].each do |verb|
          public_send(verb, address, params: { customer_id: customer.id, uuid: SecureRandom.uuid },
                      env: { "SCRIPT_NAME" => mount, "REQUEST_URI" => "#{mount}#{address}" })
          expect(response).to have_http_status(:ok), "#{host}#{mount}#{address}"
          expect(request.path_parameters).to include(controller: "public_pages", customer_id: other_customer.id, uuid: target.public_uuid)
          expect(request.path_info).to eq(address)
          expect(request.script_name).to eq(mount)
          expect(response.body).to include(target.name) if verb == :get
          expect(response.body).to be_empty if verb == :head
        end
      end
    end
    host! "shared.example.test"
    get "/#{other_customer.id}#{path}d"
    expect(response).to have_http_status(:not_found)
  end

  it "does not fall back for inactive default or retained dedicated customers" do
    PageShortcut.create!(customer_id: customer.id, path: "/", target: page)
    customer.soft_delete
    get "/"
    expect(response).to have_http_status(:not_found)
    other_customer.soft_delete
    expect(hostname.reload.customer_id).to eq(other_customer.id)
    host! "forms.example.test"
    get "/"
    expect(response).to have_http_status(:not_found)
  end

  it "keeps a missing configured default valid for bootstrap without creating a dangling hostname" do
    Rails.application.config.x.page_shortcuts.default_customer_id = 99999999
    expect(Customer.unscoped.exists?(id: 99999999)).to be(false)
    host! "unmapped.example.test"
    get "/"
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(controller: "home", action: "index")
    ["/join", "/99999999/"].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
  end

  it "keeps shared-host bootstrap sign-in and signed-in landing when the platform customer does not exist" do
    Rails.application.config.x.page_shortcuts.default_customer_id = 81721200
    expect(Customer.unscoped.exists?(id: 81721200)).to be(false)
    %i[get head].each do |verb|
      public_send(verb, "/", params: { customer_id: other_customer.id, uuid: SecureRandom.uuid })
      expect(response).to have_http_status(:ok)
      expect(request.path_parameters).to include(controller: "home", action: "index")
      expect(response.body).to be_empty if verb == :head
    end
    actor = create(:user, :member, customer: customer)
    sign_in actor
    get "/"
    expect(response).to redirect_to(Authentication::LandingPath.for(actor))
  end

  it "does not treat a known inactive default as a bootstrap tenant" do
    platform = create(:customer, id: 81721200)
    platform.update!(status: :inactive)
    Rails.application.config.x.page_shortcuts.default_customer_id = platform.id
    get "/"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
    expect(request.path_parameters).to include(controller: "page_shortcuts/unavailable", action: "show")
  end

  it "restores sign-in fallback only after an unavailable mapping is removed and no home exists" do
    mapping = PageShortcut.create!(customer_id: customer.id, path: "/", target: page)
    page.update!(launched: false)
    get "/"
    expect(response).to have_http_status(:not_found)
    mapping.destroy!
    get "/"
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(controller: "home", action: "index")
  end

  it "refreshes public navigation aliases between requests and releases the lookup after rendering" do
    enable_module!("website", customer, name: "Website")
    website = create(:website, :published, customer: customer)
    create(:website_page, :home, :published, website: website)
    inner = create(:website_page, :published, website: website, slug: "pricing")
    mapping = PageShortcut.create!(customer_id: customer.id, path: "/old-plans", target: inner)
    get website_home_path(customer.id)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("nav a").map { |link| Addressable::URI.parse(link["href"]).path }).to include("/old-plans")
    expect(Current.page_shortcuts_lookup).to be_nil
    mapping.update!(path: "/new-plans")
    get website_home_path(customer.id)
    links = Nokogiri::HTML(response.body).css("nav a").map { |link| Addressable::URI.parse(link["href"]).path }
    expect(links).to include("/new-plans")
    expect(links).not_to include("/old-plans")
    expect(Current.page_shortcuts_lookup).to be_nil
  end
end
