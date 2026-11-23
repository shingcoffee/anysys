# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcut edit recovery", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:page) { public_form("Original editable destination") }
  let(:replacement) { public_form("Replacement editable destination") }
  let(:shortcut) do
    PageShortcut.create!(customer_id: customer.id, path: "/campaign/original", target_type: "Page", target_id: page.id)
  end
  let(:index_path) { admin_maintenance_page_shortcuts_path(customer.id) }
  let(:update_path) { admin_maintenance_page_shortcut_path(customer.id, shortcut.id) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  after { Current.reset }

  def public_form(name, **attributes)
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, launched: true, name: name, **attributes)
    end
  end

  def expect_retained_edit(path:, target:)
    expect(response).to have_http_status(:unprocessable_entity)
    html = Nokogiri::HTML(response.body)
    input = html.at_css('input[name="page_shortcut[path]"]')
    select = html.at_css('select[name="page_shortcut[target]"]')
    expect(input["value"]).to eq(path)
    expect(select.at_css("option[selected]")["value"]).to eq(target)
    form = input.ancestors("form").first
    expect(form["action"]).to eq(update_path)
    expect(form.at_css('input[name="_method"]')["value"]).to eq("patch")
    expect(form["data-turbo"]).to eq("false")
    expect(html.at_css('[role="alert"]')).to be_present
    expect(html.css('form input[name="page_shortcut[path]"]').length).to eq(1)
  end

  ["duplicate shortcut", "automatic website slug"].each do |conflict|
    it "retains both stored identity and attempted destination on a #{conflict} 422, then repairs the same row" do
      original = shortcut.attributes
      if conflict == "duplicate shortcut"
        PageShortcut.create!(customer_id: customer.id, path: "/taken", target_type: "Page", target_id: replacement.id)
      else
        enable_module!("website", customer, name: "Website")
        site = create(:website, :published, customer: customer)
        create(:website_page, website: site, slug: "taken", published: false)
      end
      selector = "Page:#{replacement.id}"
      sign_in admin

      expect do
        patch update_path, params: { page_shortcut: { path: "/taken", target: selector } }
      end.not_to change(PageShortcut, :count)
      expect_retained_edit(path: "/taken", target: selector)
      expect(shortcut.reload.attributes).to eq(original)

      sign_out admin
      get "/campaign/original"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(page.name)
      expect(response.body).not_to include(replacement.name)

      sign_in admin
      expect do
        patch update_path, params: { page_shortcut: { path: "/campaign/repaired", target: selector } }
      end.not_to change(PageShortcut, :count)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(index_path)
      expect(shortcut.reload).to have_attributes(id: original.fetch("id"), customer_id: customer.id,
                                                path: "/campaign/repaired", target_type: "Page", target_id: replacement.id)
      sign_out admin
      get "/campaign/repaired"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(replacement.name)
      get "/campaign/original"
      expect(response).to have_http_status(:not_found)
      get public_page_path(customer.id, page.public_uuid)
      expect(response).to have_http_status(:ok)
    end
  end

  it "does not partially save a valid new path when its selected target went private before PATCH" do
    original = shortcut.attributes
    selector = "Page:#{replacement.id}"
    sign_in admin
    get index_path, params: { edit: shortcut.id }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css('select[name="page_shortcut[target]"] option').map { |option| option["value"] })
      .to include(selector)
    Current.set(customer: customer) { replacement.update!(visible_audiences: %w[admin member]) }

    expect do
      patch update_path, params: { page_shortcut: { path: "/campaign/new-path", target: selector } }
    end.not_to change(PageShortcut, :count)
    expect_retained_edit(path: "/campaign/new-path", target: selector)
    expect(Nokogiri::HTML(response.body).at_css('select[name="page_shortcut[target]"]')["aria-invalid"]).to eq("true")
    expect(shortcut.reload.attributes).to eq(original)
    sign_out admin
    get "/campaign/original"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.name)
    get "/campaign/new-path"
    expect(response).to have_http_status(:not_found)
  end

  it "keeps missing targets identifiable and removable on the management index without deleting another page" do
    id = shortcut.id
    deleted_name = page.name
    Current.set(customer: customer) { page.destroy! }
    replacement
    sign_in admin

    get index_path, params: { edit: id }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('input[name="page_shortcut[path]"]')["value"]).to eq(shortcut.path)
    expect(html.at_css('select[name="page_shortcut[target]"] option[selected]')["value"]).to eq("Page:#{page.id}")
    expect(response.body).to include(I18n.t("page_shortcuts.missing_destination"))
    expect(html.css("a").map { |link| link["href"] }).not_to include(shortcut.path)

    expect { delete update_path }.to change(PageShortcut, :count).by(-1)
    expect(response).to have_http_status(:see_other)
    expect(Page.exists?(replacement.id)).to be(true)
    sign_out admin
    get "/campaign/original"
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(deleted_name)
  end

  it "creates an owner-managed tenant shortcut to a shared Page without advancing any definition head" do
    other_customer = create(:customer)
    shared = Current.set(customer: nil, shared_resources_mode: true) do
      create(:page, :shared, :for_member, :for_public, launched: true, configuration: {
        metadata: {}, pages: [{ id: "page_1", fields: [
          { id: "owner-managed-copy", field_type: "paragraph", property_type: "layout", content: "Global management copy" }
        ] }]
      }.to_json)
    end
    Current.set(customer: other_customer, shared_resources_mode: false) do
      config = JSON.parse(shared.reload.configuration)
      config["pages"][0]["fields"][0]["content"] = "URL customer override copy"
      shared.configuration = config.to_json
      shared.commit_version!
    end
    global_head = shared.current_version_id
    heads = shared.page_customer_heads.pluck(:customer_id, :current_version_id)
    version_ids = shared.page_versions.ids
    owner = find_or_create_platform_owner
    sign_in owner

    expect do
      post admin_maintenance_page_shortcuts_path(other_customer.id),
           params: { customer_id: customer.id, page_shortcut: {
             path: "/shared/join", target: "Page:#{shared.id}", customer_id: owner.customer_id
           } }
    end.to change(PageShortcut, :count).by(1)
    expect(response).to have_http_status(:see_other)
    expect(PageShortcut.find_by!(customer_id: other_customer.id, path: "/shared/join").target_id).to eq(shared.id)
    sign_out owner
    get "/#{other_customer.id}/shared/join", params: { customer_id: customer.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("URL customer override copy")
    expect(response.body).not_to include("Global management copy")
    expect(shared.reload.current_version_id).to eq(global_head)
    expect(shared.page_customer_heads.pluck(:customer_id, :current_version_id)).to eq(heads)
    expect(shared.page_versions.ids).to match_array(version_ids)
  end
end
