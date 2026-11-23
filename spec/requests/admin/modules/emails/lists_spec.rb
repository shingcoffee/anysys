# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Lists", type: :request do
  include_context "as admin"

  let(:other_customer) { create(:customer) }
  let(:other_admin)    { create(:user, customer: other_customer, role: :admin) }

  let!(:email_module) { enable_module!("email", customer, name: "Email") }

  def lists_path = "/#{customer.id}/admin/modules/emails/lists"
  def list_path(list) = "#{lists_path}/#{list.id}"

  # ---------------------------------------------------------------------------
  # GET index
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/lists" do
    let(:guard_path) { lists_path }

    it_behaves_like "an admin-guarded GET"
    it "renders the list index with own lists" do
      list = create(:email_list, customer: customer)
      get lists_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(list.name)
      expect(response.body).to include(I18n.t("feature_modules.email.tabs.lists"))
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.index.description"))
    end

    it "links the list name to its detail page and exposes Edit as a row action" do
      list = create(:email_list, customer: customer, description: "Main newsletter")
      get lists_path

      name_link = Nokogiri::HTML(response.body).css("tbody td a.link").first
      expect(name_link).not_to be_nil
      expect(name_link[:href]).to eq(admin_modules_emails_list_path(customer, list))
      expect(response.body).to include("Main newsletter")
      expect(response.body).to include(I18n.t("common.actions.edit"))
      expect(response.body).to include(edit_admin_modules_emails_list_path(customer, list))
      table = Nokogiri::HTML(response.body).at_css("turbo-frame#admin-table")
      expect(table.css("[data-controller~='menu-placement']")).to be_empty
      expect(table.css("summary").map { |node| node["aria-label"] }).not_to include(I18n.t("common.actions.more"))
    end

    it "renders type as a badge and updated time as relative text" do
      create(:email_list, customer: customer, list_type: "dynamic", updated_at: 2.days.ago)
      get lists_path

      expect(response.body).to include(I18n.t("admin_modules.emails.lists.form.types.dynamic"))
      expect(response.body).to include(I18n.t("chrome.admin_table.time_ago", time: "2 days"))
      expect(response.body).to include("<time")
    end

    it "filters by list type" do
      create(:email_list, customer: customer, name: "Static One", list_type: "static")
      create(:email_list, customer: customer, name: "Dynamic One", list_type: "dynamic")

      get lists_path, params: { list_type: "static" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Static One")
      expect(response.body).not_to include("Dynamic One")
    end

    it "returns JSON options for the send-activity wizard refresh" do
      own = create(:email_list, customer: customer, name: "Own List")
      create(:email_list, customer: other_customer, name: "Foreign List")

      get lists_path, as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      expect(payload).to contain_exactly({ "id" => own.id, "name" => "Own List" })
    end

    it "does not show another customer's lists in the response" do
      other_list = create(:email_list, customer: other_customer)
      get lists_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_list.name)
    end

    it "does not render a status badge column label as Status for lists" do
      create(:email_list, customer: customer, name: "NoStatusList")
      get lists_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/<th[^>]*>\s*(?:<a[^>]*>)?\s*Status/m)
    end
  end

  # ---------------------------------------------------------------------------
  # GET new
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/lists/new" do
    let(:guard_path) { "#{lists_path}/new" }

    it_behaves_like "an admin-guarded GET"
    it "marks name and list type as required" do
      get "#{lists_path}/new"
      expect(response.body).to include("form-label-required")
      expect(response.body).to match(/<input[^>]*name="email_list\[name\]"[^>]*\brequired\b|<input[^>]*\brequired\b[^>]*name="email_list\[name\]"/)
      expect(response.body).to match(/<select[^>]*name="email_list\[list_type\]"[^>]*\brequired\b|<select[^>]*\brequired\b[^>]*name="email_list\[list_type\]"/)
    end

    it "renders dynamic segment preview controls" do
      get "#{lists_path}/new"

      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.button"))
      expect(response.body).to include('id="email_list_preview"')
      expect(response.body).to include("email-list-form-preview-url-value")
      expect(response.body).to include("email-list-form-loading-label-value")
      expect(response.body).to include(I18n.t("common.status.loading"))
      expect(response.body).to include('data-email-list-form-target="previewModal"')
      expect(response.body).to include('class="form-label">Audience conditions')
      expect(response.body).to include('data-email-list-form-target="previewButton"')
      expect(response.body).to include("rounded-xl border border-border-subtle")
    end

    it "renders fields under the param key the controller requires (email_list[...])" do
      # Regression guard: form_with would derive 'emails_list' from the
      # namespaced model; the controller requires :email_list (and the segment
      # builder hidden field is email_list[segment_rules_json]).
      get "#{lists_path}/new"
      expect(response.body).to include('name="email_list[name]"')
      expect(response.body).to include('name="email_list[list_type]"')
      expect(response.body).to include('name="email_list[segment_rules_json]"')
      expect(response.body).not_to include('name="emails_list[name]"')
    end

    it "does not render a status field" do
      get "#{lists_path}/new"
      expect(response.body).not_to include('name="email_list[status]"')
    end
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/lists" do
    let(:guard_path) { lists_path }

    it_behaves_like "an admin-guarded request", :post
    it "creates a list and redirects to index" do
      expect {
        post lists_path, params: { email_list: { name: "Newsletter" } }
      }.to change(Emails::Audience::List, :count).by(1)

      created = Emails::Audience::List.unscoped.order(:created_at).last
      expect(response).to redirect_to(/emails\/lists/)
      expect(created.customer_id).to eq(customer.id)
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect {
        post lists_path, params: { email_list: { name: "Newsletter" } }
      }.not_to change(Emails::Audience::List, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "creates a list with description and redirects on success" do
      post lists_path,
           params: { email_list: { name: "Newsletter", description: "main list" } }
      expect(response).to redirect_to(/emails\/lists/)
      expect(Emails::Audience::List.where(customer: customer, name: "Newsletter")).to exist
    end

    it "re-renders new with 422 on blank name" do
      post lists_path,
           params: { email_list: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "persists dynamic segment_rules_json" do
      rules = {
        "match" => "all",
        "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }]
      }
      post lists_path,
           params: {
             email_list: {
               name: "Dynamic",
               list_type: "dynamic",
               segment_rules_json: rules.to_json
             }
           }

      list = Emails::Audience::List.where(customer: customer, name: "Dynamic").last
      expect(list).to be_present
      expect(list).to be_dynamic
      expect(list.segment_rules).to eq(rules)
    end

    it "re-renders with an error on malformed segment_rules_json" do
      post lists_path,
           params: {
             email_list: {
               name: "Broken",
               list_type: "dynamic",
               segment_rules_json: "{not valid json"
             }
           }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
    end

    it "re-renders with an error when segment_rules_json is a JSON array" do
      post lists_path,
           params: {
             email_list: {
               name: "BrokenArray",
               list_type: "dynamic",
               segment_rules_json: "[]"
             }
           }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
    end

    it "rejects a syntactically valid but semantically invalid dynamic audience before saving" do
      rules = { conditions: [{ field: "first_name", operator: "unknown", value: "Ada" }] }
      expect {
        post lists_path, params: { email_list: { name: "Broken semantics", list_type: "dynamic", segment_rules_json: rules.to_json } }
      }.not_to change(Emails::Audience::List, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
    end

    it "rejects oversized audience JSON before parsing or persistence" do
      raw = " " * (Emails::Audience::Contracts::SegmentRules::MAX_JSON_BYTES + 1)
      expect {
        post lists_path, params: { email_list: { name: "Oversized", list_type: "dynamic", segment_rules_json: raw } }
      }.not_to change(Emails::Audience::List, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # GET show
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/lists/:id" do
    let(:list) { create(:email_list, customer: customer) }
    let(:guard_path) { list_path(list) }

    it_behaves_like "an admin-guarded GET"
    it "renders the detail page with metadata, badges, and Edit/Delete actions" do
      list = create(:email_list, customer: customer, name: "Newsletter",
                    description: "Weekly digest", list_type: "dynamic",
                    segment_rules: { "match" => "all", "conditions" => [] })

      get list_path(list)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Newsletter", "Weekly digest")
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.form.types.dynamic"))
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.show.audience"))
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.show.segment_rules"))
      expect(response.body).to include(edit_admin_modules_emails_list_path(customer, list))
      expect(response.body).to include(I18n.t("common.actions.delete"))
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.show.delete_confirm"))
      expect(response.body).to include('data-turbo-method="delete"')
    end

    it "lists member emails for a static list" do
      list = create(:email_list, :static, customer: customer)
      user = create(:user, customer: customer, email: "member@example.com")
      create(:email_list_membership, email_list: list, user: user)

      get list_path(list)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.show.members"))
      expect(response.body).to include("member@example.com")
    end

    it "does not dump every static member on one page" do
      stub_const("ModuleEntriesResolver::MAX_PER_PAGE", 2)
      list = create(:email_list, :static, customer: customer)
      %w[aaa@example.com bbb@example.com ccc@example.com].each do |email|
        member = create(:user, customer: customer, email: email)
        create(:email_list_membership, email_list: list, user: member)
      end

      get list_path(list)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("aaa@example.com")
      expect(response.body).to include("bbb@example.com")
      expect(response.body).not_to include("ccc@example.com")
    end

    it "returns 404 for another tenant's list" do
      other_list = create(:email_list, customer: other_customer)
      get list_path(other_list)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # GET edit
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/lists/:id/edit" do
    let(:list) { create(:email_list, customer: customer) }
    let(:guard_path) { "#{list_path(list)}/edit" }

    it_behaves_like "an admin-guarded GET"
    it "renders the edit form for own record" do
      list = create(:email_list, customer: customer)
      get "#{list_path(list)}/edit"
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 when editing another customer's list" do
      other_list = create(:email_list, customer: other_customer)
      get "#{list_path(other_list)}/edit"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update
  # ---------------------------------------------------------------------------
  describe "PATCH /:cid/admin/modules/emails/lists/:id" do
    let(:list) { create(:email_list, customer: customer) }
    let(:guard_path) { list_path(list) }

    it_behaves_like "an admin-guarded request", :patch
    it "updates the list and redirects to show" do
      list = create(:email_list, customer: customer)
      patch list_path(list),
            params: { email_list: { name: "Updated Name" } }
      expect(response).to redirect_to(/emails\/lists\/#{list.id}/)
      expect(list.reload.name).to eq("Updated Name")
    end

    it "preserves dynamic rules when the type and rules are omitted from a metadata update" do
      rules = { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] }
      list = create(:email_list, customer: customer, list_type: "dynamic", segment_rules: rules)

      patch list_path(list), params: { email_list: { description: "New description" } }

      expect(response).to have_http_status(:redirect)
      expect(list.reload).to have_attributes(list_type: "dynamic", segment_rules: rules, description: "New description")
    end

    it "rejects invalid replacement rules without changing list metadata or its existing audience" do
      list = create(:email_list, :dynamic, customer: customer)
      original_name, original_rules = list.name, list.segment_rules
      invalid = { conditions: [{ field: "created_at", operator: "after", value: "not-a-date" }] }

      patch list_path(list), params: { email_list: { name: "Rejected name", segment_rules_json: invalid.to_json } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
      expect(list.reload).to have_attributes(name: original_name, segment_rules: original_rules)
    end

    it "preserves a static list and its memberships when list_type is omitted" do
      list = create(:email_list, :static, customer: customer)
      user = create(:user, customer: customer)
      create(:email_list_membership, email_list: list, user: user)

      patch list_path(list), params: { email_list: { name: "Metadata only" } }

      expect(response).to have_http_status(:redirect)
      expect(list.reload.list_type).to eq("static")
      expect(list.users).to contain_exactly(user)
    end

    it "rejects an unknown explicit list type instead of silently converting it to dynamic" do
      list = create(:email_list, :static, customer: customer)

      patch list_path(list), params: { email_list: { list_type: "unexpected" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(list.reload.list_type).to eq("static")
    end

    it "clears dynamic rules only when an empty rules value is explicitly submitted" do
      list = create(:email_list, customer: customer, segment_rules: { "match" => "any", "conditions" => [] })

      patch list_path(list), params: { email_list: { segment_rules_json: "" } }

      expect(response).to have_http_status(:redirect)
      expect(list.reload.segment_rules).to eq({})
    end

    it "rejects a non-string rules object without changing the existing rules" do
      rules = { "match" => "all", "conditions" => [] }
      list = create(:email_list, customer: customer, segment_rules: rules)

      patch list_path(list), params: { email_list: { segment_rules_json: { injected: "rules" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(list.reload.segment_rules).to eq(rules)
    end

    it "re-renders edit with 422 on blank name" do
      list = create(:email_list, customer: customer)
      patch list_path(list),
            params: { email_list: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 when updating another customer's list" do
      other_list = create(:email_list, customer: other_customer)
      patch list_path(other_list),
            params: { email_list: { name: "Hijack" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------
  describe "DELETE /:cid/admin/modules/emails/lists/:id" do
    let(:list) { create(:email_list, customer: customer) }
    let(:guard_path) { list_path(list) }

    it_behaves_like "an admin-guarded request", :delete
    it "destroys the list and redirects to index" do
      list = create(:email_list, customer: customer)
      expect {
        delete list_path(list)
      }.to change(Emails::Audience::List, :count).by(-1)
      expect(response).to redirect_to(/emails\/lists/)
      expect(Emails::Audience::List.find_by(id: list.id)).to be_nil
    end

    it "redirects with alert when campaigns reference the list" do
      list = create(:email_list, customer: customer)
      create(:email_send_activity, customer: customer, email_lists: [list])
      delete list_path(list)
      expect(response).to redirect_to(/emails\/lists/)
      follow_redirect!
      expect(response.body).to include("Cannot delete list")
    end

    it "returns 404 when deleting another customer's list" do
      other_list = create(:email_list, customer: other_customer)
      expect {
        delete list_path(other_list)
      }.not_to change(Emails::Audience::List, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "membership sync via email_list_static_emails" do
    let!(:member_user) { create(:user, customer: customer, email: "member@example.com") }

    it "adds memberships on create when emails are posted" do
      expect {
        post "/#{customer.id}/admin/modules/emails/lists",
             params: {
               email_list: { name: "Newsletter", list_type: "static" },
               email_list_static_emails: "member@example.com"
             }
      }.to change(Emails::Audience::ListMembership, :count).by(1)

      list = Emails::Audience::List.for_customer(customer.id).order(:id).last
      expect(list.users).to include(member_user)
    end

    it "does not wipe memberships on metadata-only update" do
      list = create(:email_list, :static, customer: customer, name: "Keepers")
      create(:email_list_membership, email_list: list, user: member_user)

      patch "/#{customer.id}/admin/modules/emails/lists/#{list.id}",
            params: { email_list: { name: "Keepers Renamed", list_type: "static" } }

      expect(list.reload.name).to eq("Keepers Renamed")
      expect(list.users).to include(member_user)
    end

    it "matches a mixed-case stored email against a downcased textarea" do
      mixed = create(:user, customer: customer, email: "ada.lovelace@example.com")
      mixed.update_columns(email: "Ada.Lovelace@Example.com")
      list = create(:email_list, :static, customer: customer)
      create(:email_list_membership, email_list: list, user: mixed)

      patch "/#{customer.id}/admin/modules/emails/lists/#{list.id}",
            params: {
              email_list: { name: list.name, list_type: "static" },
              email_list_static_emails: "ada.lovelace@example.com"
            }

      expect(list.reload.users).to include(mixed)
    end

    it "replaces memberships when emails are posted on update" do
      list = create(:email_list, :static, customer: customer)
      create(:email_list_membership, email_list: list, user: member_user)
      other = create(:user, customer: customer, email: "other@example.com")

      patch "/#{customer.id}/admin/modules/emails/lists/#{list.id}",
            params: {
              email_list: { name: list.name, list_type: "static" },
              email_list_static_emails: "other@example.com"
            }

      expect(list.reload.users).to contain_exactly(other)
    end

    it "does not create a user for an unknown address" do
      expect {
        post "/#{customer.id}/admin/modules/emails/lists",
             params: {
               email_list: { name: "Strangers", list_type: "static" },
               email_list_static_emails: "nobody@example.com"
             }
      }.not_to change(Authentication::User, :count)

      list = Emails::Audience::List.for_customer(customer.id).order(:id).last
      expect(list.users).to be_empty
      expect(flash[:alert]).to include("nobody@example.com")
    end

    it "does not squat an email that already belongs to another tenant" do
      victim = create(:user, customer: other_customer, email: "victim@example.com")

      expect {
        post "/#{customer.id}/admin/modules/emails/lists",
             params: {
               email_list: { name: "Poach", list_type: "static" },
               email_list_static_emails: "victim@example.com"
             }
      }.not_to change(Authentication::User, :count)

      expect(victim.reload.customer_id).to eq(other_customer.id)
      list = Emails::Audience::List.for_customer(customer.id).order(:id).last
      expect(list.users).to be_empty
    end
  end

  describe "POST /:cid/admin/modules/emails/lists/preview" do
    def preview_path = "#{lists_path}/preview"
    let(:guard_path) { preview_path }

    it_behaves_like "an admin-guarded request", :post

    let(:rules) do
      {
        "match" => "all",
        "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }]
      }
    end

    it "returns matching tenant subscribers in the preview frame" do
      ada = create(:user, customer: customer, first_name: "Ada", email: "ada@example.com")
      create(:user, customer: customer, first_name: "Bob", email: "bob@example.com")
      create(:user, customer: other_customer, first_name: "Ada", email: "other-ada@example.com")

      post preview_path, params: { segment_rules_json: rules.to_json },
           headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="email_list_preview"').or include("email_list_preview")
      expect(response.body).to include("ada@example.com")
      expect(response.body).not_to include("bob@example.com")
      expect(response.body).not_to include("other-ada@example.com")
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.match_count", count: 1))
    end

    it "renders empty state when no subscribers match" do
      create(:user, customer: customer, first_name: "Bob")
      post preview_path, params: { segment_rules_json: rules.to_json },
           headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.empty_title"))
    end

    it "returns 422 with malformed rules message on bad JSON" do
      post preview_path, params: { segment_rules_json: "{not-json" },
           headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.malformed"))
    end

    it "returns 422 when segment_rules_json is a JSON array" do
      post preview_path, params: { segment_rules_json: "[]" },
           headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.malformed"))
    end

    it "returns 422 when segment_rules_json is a nested hash instead of 500ing" do
      post preview_path, params: { segment_rules_json: { foo: "bar" } },
           headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.malformed"))
    end

    it "rejects unknown operators in preview rather than revealing every tenant user" do
      user = create(:user, customer: customer, email: "must-not-expand@example.com")
      malformed = { conditions: [{ field: "first_name", operator: "unknown", value: "Ada" }] }
      post preview_path, params: { segment_rules_json: malformed.to_json }, headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.emails.lists.preview.malformed"))
      expect(response.body).not_to include(user.email)
    end

    it "rejects oversized preview input using the same byte bound as writes" do
      raw = " " * (Emails::Audience::Contracts::SegmentRules::MAX_JSON_BYTES + 1)
      post preview_path, params: { segment_rules_json: raw }, headers: { "Turbo-Frame" => "email_list_preview" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "preserves the intentionally empty all-tenant preview behavior" do
      own = create(:user, customer: customer, email: "own-empty@example.com")
      foreign = create(:user, customer: other_customer, email: "foreign-empty@example.com")
      post preview_path, params: { segment_rules_json: "{}" }, headers: { "Turbo-Frame" => "email_list_preview" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(own.email)
      expect(response.body).not_to include(foreign.email)
    end
  end
end
