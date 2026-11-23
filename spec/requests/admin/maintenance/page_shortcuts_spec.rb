# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin maintenance page shortcuts", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:index_path) { admin_maintenance_page_shortcuts_path(customer.id) }
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Public destination")
    end
  end
  let(:target) { "Page:#{page.id}" }
  let(:shortcut) { PageShortcut.create!(customer_id: customer.id, path: "/join", target_type: "Page", target_id: page.id) }

  def shortcut_path(record = shortcut)
    admin_maintenance_page_shortcut_path(customer.id, record.id)
  end

  def foreign_shortcut
    foreign_page = Current.set(customer: other_customer) do
      create(:page, :for_member, :for_public, customer: other_customer, launched: true, name: "Foreign destination")
    end
    PageShortcut.create!(customer_id: other_customer.id, path: "/foreign", target_type: "Page", target_id: foreign_page.id)
  end

  it "authenticates anonymous index, create, update and destroy requests" do
    id = shortcut.id
    [[:get, index_path], [:post, index_path], [:patch, shortcut_path], [:delete, shortcut_path]].each do |verb, path|
      expect do
        public_send(verb, path, params: { page_shortcut: { path: "/forged", target: target } })
      end.not_to change(PageShortcut, :count)
      expect(response).to redirect_to(new_user_session_path)
      expect(PageShortcut.find(id).path).to eq("/join")
    end
  end

  it "denies members on every management action without mutating records" do
    id = shortcut.id
    sign_in create(:user, :member, customer: customer)
    [[:get, index_path], [:post, index_path], [:patch, shortcut_path], [:delete, shortcut_path]].each do |verb, path|
      expect do
        public_send(verb, path, params: { page_shortcut: { path: "/forged", target: target } },
                                headers: { "Accept" => "application/json" })
      end.not_to change(PageShortcut, :count)
      expect(response).to have_http_status(:forbidden)
      expect(PageShortcut.find(id).path).to eq("/join")
    end
  end

  it "denies cross-tenant admins before listing or mutating the URL customer's records" do
    shortcut
    sign_in create(:user, :admin, customer: other_customer)
    [[:get, index_path], [:post, index_path], [:patch, shortcut_path], [:delete, shortcut_path]].each do |verb, path|
      expect do
        public_send(verb, path, params: { page_shortcut: { path: "/forged", target: target } },
                                headers: { "Accept" => "application/json" })
      end.not_to change(PageShortcut, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "as a same-tenant admin" do
    before { sign_in admin }

    it "lists only URL-tenant mappings and prefills a scoped edit on the same index" do
      shortcut
      foreign = foreign_shortcut
      get index_path, params: { edit: shortcut.id }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('input[name="page_shortcut[path]"]')["value"]).to eq("/join")
      expect(html.at_css('option[selected]')["value"]).to eq(target)
      expect(response.body).not_to include(foreign.path)
      expect(response.body).not_to include("Foreign destination")
      expect(html.at_css("a[href*='/domains#domain-form']")).to be_nil
    end

    it "derives customer and target identity from authorized context and allowlisted form fields" do
      expect do
        post index_path, params: { page_shortcut: { path: "/registration", target: target,
                                                   customer_id: other_customer.id, target_type: "Authentication::User",
                                                   target_id: admin.id } }
      end.to change(PageShortcut, :count).by(1)
      expect(PageShortcut.last).to have_attributes(customer_id: customer.id, path: "/registration", target_type: "Page", target_id: page.id)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(index_path)
      expect(flash[:notice]).to eq(I18n.t("page_shortcuts.flash.saved"))
    end

    it "updates atomically through the scoped row and redirects with 303" do
      id = shortcut.id
      expect do
        patch shortcut_path, params: { page_shortcut: { path: "/registration", target: target, customer_id: other_customer.id } }
      end.not_to change(PageShortcut, :count)
      expect(shortcut.reload).to have_attributes(id: id, customer_id: customer.id, path: "/registration")
      expect(response).to have_http_status(:see_other)
    end

    it "renders the index with 422 and retains invalid create values" do
      expect do
        post index_path, params: { page_shortcut: { path: "/admin/forged", target: target } }
      end.not_to change(PageShortcut, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('input[name="page_shortcut[path]"]')["value"]).to eq("/admin/forged")
      expect(html.at_css('option[selected]')["value"]).to eq(target)
    end

    it "retains the original row and edit state after an invalid update" do
      id = shortcut.id
      patch shortcut_path, params: { page_shortcut: { path: "/admin/forged", target: target } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PageShortcut.find(id).path).to eq("/join")
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('input[name="page_shortcut[path]"]')["value"]).to eq("/admin/forged")
      expect(html.at_css('form[action="' + shortcut_path + '"] input[name="_method"]')["value"]).to eq("patch")
    end

    it "rejects another customer's edit, update and delete IDs even under the actor's URL" do
      foreign = foreign_shortcut
      get index_path, params: { edit: foreign.id }
      expect(response).to have_http_status(:not_found)
      patch shortcut_path(foreign), params: { page_shortcut: { path: "/forged", target: target } }
      expect(response).to have_http_status(:not_found)
      expect { delete shortcut_path(foreign) }.not_to change(PageShortcut, :count)
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.path).to eq("/foreign")
    end

    it "deletes only the shortcut, preserving its target" do
      shortcut
      expect { delete shortcut_path }.to change(PageShortcut, :count).by(-1)
      expect(Page.exists?(page.id)).to be(true)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(index_path)
      expect(flash[:notice]).to eq(I18n.t("page_shortcuts.flash.deleted"))
    end

    it "offers only published tenant website pages and launched public tenant/shared Pages" do
      enable_module!("website", customer, name: "Website")
      website = create(:website, :published, customer: customer)
      home = create(:website_page, :home, :published, website: website)
      inner = create(:website_page, :published, website: website)
      draft = create(:website_page, website: website)
      invalid_slug = create(:website_page, :published, website: website)
      invalid_slug.update_columns(slug: "invalid/slug")
      own = page
      shared = create(:page, :shared, :for_member, :for_public, launched: true)
      private_page = create(:page, :for_member, customer: customer, launched: true)
      unlaunched = create(:page, :for_member, :for_public, customer: customer, launched: false)
      missing_uuid = create(:page, :for_member, :for_public, customer: customer, launched: true)
      missing_uuid.update_columns(public_uuid: nil)
      foreign = foreign_shortcut

      get index_path
      expect(response).to have_http_status(:ok)
      values = Nokogiri::HTML(response.body).css('select[name="page_shortcut[target]"] option').map { |option| option["value"] }
      expect(values).to include("WebsitePage:#{home.id}", "WebsitePage:#{inner.id}", "Page:#{own.id}", "Page:#{shared.id}")
      expect(values).not_to include("WebsitePage:#{draft.id}", "WebsitePage:#{invalid_slug.id}", "Page:#{private_page.id}",
                                   "Page:#{unlaunched.id}", "Page:#{missing_uuid.id}", "Page:#{foreign.target_id}")
    end

    it "preserves website position and Page name ordering with localized scalar destination labels" do
      enable_module!("website", customer, name: "Website")
      website = create(:website, :published, customer: customer)
      later = create(:website_page, :published, website: website, title: "Later website", position: 2)
      home = create(:website_page, :home, :published, website: website, title: "Earlier home", position: 1)
      zebra = create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Zebra form")
      alpha = create(:page, :shared, :for_member, :for_public, launched: true, name: "Alpha form")

      %w[en zh-CN].each do |locale|
        get index_path, params: { locale: locale }
        expect(response).to have_http_status(:ok)
        options = Nokogiri::HTML(response.body).css('select[name="page_shortcut[target]"] option').reject { |option| option["value"].blank? }
        expect(options.map { |option| option["value"] }).to eq([
          "WebsitePage:#{home.id}", "WebsitePage:#{later.id}", "Page:#{alpha.id}", "Page:#{zebra.id}"
        ])
        expected_labels = [[home, "website_page"], [later, "website_page"], [alpha, "public_page"], [zebra, "public_page"]].map do |record, type|
          I18n.t("page_shortcuts.destination_label", locale: locale,
                 type: I18n.t("page_shortcuts.target_types.#{type}", locale: locale),
                 title: record.is_a?(WebsitePage) ? record.title : record.name)
        end
        expect(options.map(&:text)).to eq(expected_labels)
      end
    end

    it "omits website options when the website or module is unavailable" do
      feature_module = enable_module!("website", customer, name: "Website")
      website = create(:website, :published, customer: customer)
      home = create(:website_page, :home, :published, website: website)
      page

      website.update!(published: false)
      get index_path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css('select[name="page_shortcut[target]"] option').map { |option| option["value"] })
        .not_to include("WebsitePage:#{home.id}")

      website.update!(published: true)
      FeatureModules::CustomerAssignment.find_by!(customer_id: customer.id, feature_module: feature_module).update!(status: :suspended)
      get index_path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css('select[name="page_shortcut[target]"] option').map { |option| option["value"] })
        .not_to include("WebsitePage:#{home.id}")
    end

    it "keeps index queries bounded as mappings grow without instantiating Pages or loading their definitions" do
      shortcut
      get index_path
      expect(response).to have_http_status(:ok)

      page_loads = []
      definition_queries = []
      instantiations = ->(_name, _start, _finish, _id, payload) { page_loads << payload if payload[:class_name] == "Page" }
      queries = lambda do |_name, _start, _finish, _id, payload|
        definition_queries << payload[:sql] if payload[:sql].match?(/\bFROM\s+"?(?:page_versions|page_customer_heads|page_configuration_contents)\b/i)
      end
      measure_index = lambda do
        count = nil
        ActiveSupport::Notifications.subscribed(instantiations, "instantiation.active_record") do
          ActiveSupport::Notifications.subscribed(queries, "sql.active_record") do
            count = count_queries { get index_path }
          end
        end
        expect(response).to have_http_status(:ok)
        count
      end
      baseline = measure_index.call
      # Reuse the bound entity so growing destinations does not also grow the
      # unrelated admin sidebar's entity-definition catalog.
      8.times do |number|
        destination = Current.set(customer: customer) do
          create(:page, :for_member, :for_public, customer: customer, entity: page.entity, launched: true, name: "Scalar destination #{number}")
        end
        PageShortcut.create!(customer_id: customer.id, path: "/campaign/scalar-#{number}", target_type: "Page", target_id: destination.id)
      end

      expect(measure_index.call).to be <= baseline
      expect(page_loads).to be_empty
      expect(definition_queries).to be_empty
    end

    it "does not expose a platform CUD namespace" do
      post "/#{customer.id}/admin/maintenance/platform/page_shortcuts",
           params: { page_shortcut: { path: "/forged", target: target } }
      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not offer a separate domain management link to the platform owner" do
    sign_in find_or_create_platform_owner
    get index_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("main a[href*='/domains']")).to be_nil
  end

  it "permits the pinned owner to manage a URL tenant while still scoping each row and target" do
    sign_in find_or_create_platform_owner
    foreign = foreign_shortcut
    post index_path, params: { page_shortcut: { path: "/owner-created", target: target } }
    expect(response).to have_http_status(:see_other)
    expect(PageShortcut.last.customer_id).to eq(customer.id)
    patch shortcut_path(foreign), params: { page_shortcut: { path: "/forged", target: target } }
    expect(response).to have_http_status(:not_found)
    post index_path, params: { page_shortcut: { path: "/foreign-target", target: "Page:#{foreign.target_id}" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(foreign.reload.path).to eq("/foreign")
  end
end
