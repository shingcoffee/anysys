# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::Admin::Users", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { find_or_create_feature_module!("authentication") }
  let(:admin_user) { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { admin_user }
  let(:users_index_path) { admin_modules_authentication_users_path(customer.id) }
  let(:guard_path) { users_index_path }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    sign_in admin_user
  end

  it_behaves_like "an admin-guarded GET"

  describe "GET show — auth guards" do
    let!(:user) { create(:user, customer: customer) }
    let(:guard_path) { admin_modules_authentication_user_path(customer.id, user) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { new_admin_modules_authentication_user_path(customer.id) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { users_index_path }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "GET edit — auth guards" do
    let!(:user) { create(:user, customer: customer) }
    let(:guard_path) { edit_admin_modules_authentication_user_path(customer.id, user) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let!(:user) { create(:user, customer: customer) }
    let(:guard_path) { admin_modules_authentication_user_path(customer.id, user) }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "POST activation — auth guards" do
    let!(:user) { create(:user, :inactive, customer: customer) }
    let(:guard_path) { admin_modules_authentication_user_activation_path(customer.id, user) }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "DELETE activation — auth guards" do
    let!(:user) { create(:user, customer: customer) }
    let(:guard_path) { admin_modules_authentication_user_activation_path(customer.id, user) }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "POST mfa_reset — auth guards" do
    let!(:user) { create(:user, customer: customer) }
    let(:guard_path) { admin_modules_authentication_user_mfa_reset_path(customer.id, user) }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "DELETE user — auth guards" do
    let!(:user) { create(:user, customer: customer) }
    let(:guard_path) { admin_modules_authentication_user_path(customer.id, user) }

    it_behaves_like "an admin-guarded request", :delete
  end


  # ==========================================================================
  # Authorization
  # ==========================================================================

  describe "authorization" do
    it "allows the platform owner to reach any customer's admin area" do
      sign_in find_or_create_platform_owner
      get users_index_path
      expect(response).to have_http_status(:success)
    end

    it "redirects a member to their own member surface" do
      member = create(:user, :member, customer: customer, password: "password123")
      sign_in member
      get users_index_path
      # Access denials keep the user inside their own tenant, on a surface
      # their role can actually open.
      expect(response).to redirect_to("/#{customer.id}/member")
    end

    # A user carrying no role row resolves to the member surface, which the
    # role gate denies in turn. Answer terminally instead of bouncing between
    # the two forever.
    it "answers 403 rather than looping when the landing surface is itself denied" do
      sign_in create(:user, customer: customer, password: "password123")
      get "/#{customer.id}/member"
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ==========================================================================
  # GET /admin/users
  # ==========================================================================

  describe "GET /:customer_id/admin/users" do
    let!(:member_user) { create(:user, :member, customer: customer, first_name: "Alice", last_name: "Member") }
    let!(:other_user) { create(:user, :member, customer: customer, first_name: "Bob", last_name: "Other") }

    it "lists members by default and keeps other roles behind the role filter" do
      unassigned = create(:user, customer: customer, first_name: "Casey", last_name: "Unassigned")

      get users_index_path
      rows = desktop_tbody(response.body)
      expect(rows).to include("Alice", "Bob")
      expect(rows).not_to include(admin_user.email)
      expect(rows).not_to include("Casey")
      expect(response.body).to include(%(value="member" selected))
      expect(response.body).not_to include(I18n.t("chrome.admin_table.remove_filter", label: I18n.t("common.labels.role")))

      get users_index_path, params: { role: "all" }
      expect(desktop_tbody(response.body)).to include(admin_user.email, "Alice", "Casey")
      expect(response.body).to include(I18n.t("admin_modules.users.index.all_roles"))
    end

    it "filters by search term" do
      get users_index_path, params: { q: "alice" }
      expect(response.body).to include("Alice")
      expect(response.body).not_to include("Bob")
    end

    it "filters by role" do
      get users_index_path, params: { role: "admin" }
      expect(response.body).to include(admin_user.first_name)
      expect(response.body).not_to include("Alice")
    end

    it "filters by status" do
      member_user.update!(status: :inactive)
      get users_index_path, params: { status: "inactive" }
      expect(response.body).to include("Alice")
      expect(response.body).not_to include("Bob")
    end

    it "links the id and the name to the detail page and keeps the directory columns only" do
      get users_index_path

      path = admin_modules_authentication_user_path(customer.id, member_user)
      expect(response.body).to match(%r{href="#{Regexp.escape(path)}"[^>]*>\s*<span[^>]*>#{member_user.id}</span>})
      expect(response.body).to match(%r{href="#{Regexp.escape(path)}"[^>]*>\s*#{Regexp.escape(member_user.full_name)}\s*</a>})
      expect(response.body).to include(I18n.l(member_user.created_at, format: :long))
      thead = response.body[response.body.index("<thead")..response.body.index("</thead>")]
      expect(thead.index("sort=id")).to be < thead.index("sort=full_name")
      expect(thead.index("sort=last_sign_in_at")).to be < thead.index("sort=created_at")
      [
        I18n.t("common.labels.name"), I18n.t("common.labels.email"), I18n.t("common.labels.role"),
        I18n.t("common.labels.status"), I18n.t("common.labels.mfa"), I18n.t("common.labels.last_sign_in"),
        I18n.t("common.labels.created_at")
      ].each { |label| expect(thead).to include(label) }
      [
        I18n.t("admin_modules.users.show.sign_in_count"), I18n.t("admin_modules.users.show.failed_attempts"),
        I18n.t("admin_modules.users.show.current_sign_in"), I18n.t("admin_modules.users.show.current_sign_in_ip"),
        I18n.t("admin_modules.users.show.last_sign_in_ip"),
        I18n.t("common.labels.updated_at")
      ].each { |label| expect(thead).not_to include(label) }
      expect(response.body).not_to include("/activation")
      expect(response.body).not_to include("mfa_reset")
      expect(response.body).not_to include(edit_admin_modules_authentication_user_path(customer.id, member_user))
    end

    it "finds a user by id and shows the empty state for an unknown id" do
      get users_index_path, params: { q: member_user.id.to_s }
      expect(response.body).to include("Alice")

      get users_index_path, params: { q: "999999999" }
      expect(response.body).to include(I18n.t("chrome.admin_table.no_matches_html", query: "999999999"))
      expect(response.body).not_to include("Alice")
    end

    it "sorts by name and by create time" do
      member_user.update_column(:created_at, Time.zone.local(2026, 1, 2, 9, 0))
      other_user.update_column(:created_at, Time.zone.local(2026, 3, 4, 9, 0))

      get users_index_path, params: { sort: "full_name", dir: "asc" }
      expect(response).to have_http_status(:ok)
      name_body = desktop_tbody(response.body)
      expect(name_body.index("Alice")).to be < name_body.index("Bob")

      get users_index_path, params: { sort: "created_at", dir: "asc" }
      expect(response).to have_http_status(:ok)
      created_body = desktop_tbody(response.body)
      expect(created_body.index("Alice")).to be < created_body.index("Bob")
      expect(created_body).to include(I18n.l(member_user.reload.created_at, format: :long))
    end

    it "sorts by id" do
      get users_index_path, params: { sort: "id", dir: "desc" }

      expect(response).to have_http_status(:ok)
      desktop = response.body.split('<div class="hidden sm:block', 2).last
      tbody = desktop[desktop.index("<tbody")..desktop.index("</tbody>")]
      ids = tbody.scan(%r{/admin/modules/authentication/users/(\d+)"}).flatten.map(&:to_i)
      expect(ids.each_slice(2).to_a).to all(satisfy { |pair| pair.uniq.size == 1 })
      expect(ids.each_slice(2).map(&:first)).to eq([member_user.id, other_user.id].sort.reverse)
    end

    it "does not list users from other tenants" do
      other_customer = create(:customer)
      create(:user, customer: other_customer, first_name: "OtherTenant")
      get users_index_path
      expect(response.body).not_to include("OtherTenant")
    end

    def desktop_tbody(body)
      desktop = body.split('<div class="hidden sm:block', 2).last
      desktop[desktop.index("<tbody")..desktop.index("</tbody>")]
    end
  end

  # ==========================================================================
  # GET /admin/users/:id
  # ==========================================================================

  describe "GET /:customer_id/admin/users/:id" do
    let!(:user) { create(:user, :member, customer: customer, first_name: "Alice", last_name: "Wonderland") }

    it "shows user details" do
      get admin_modules_authentication_user_path(customer.id, user)
      expect(response.body).to include("Alice")
      expect(response.body).to include("Wonderland")
      expect(response.body).to include(user.email)
    end

    it "localizes created_at instead of ISO strftime" do
      get admin_modules_authentication_user_path(customer.id, user)
      expect(response.body).to include(I18n.l(user.created_at, format: :long))
      expect(response.body).not_to include(user.created_at.strftime("%Y-%m-%d %H:%M:%S"))
    end

    it "localizes timestamps in zh-CN" do
      get admin_modules_authentication_user_path(customer.id, user), params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.l(user.created_at, format: :long, locale: :"zh-CN"))
    end

    it "localizes the reserved role instead of capitalizing the key" do
      get admin_modules_authentication_user_path(customer.id, user), params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.t("common.roles.member", locale: :"zh-CN"))
    end

    it "localizes trusted-device last used and expiry" do
      device = Authentication::TrustedDevice.create!(
        customer_id: user.customer_id, user_id: user.id,
        token_digest: SecureRandom.hex(16), expires_at: Time.zone.local(2026, 12, 31, 9, 0),
        last_used_at: Time.zone.local(2026, 6, 15, 10, 30)
      )
      get admin_modules_authentication_user_path(customer.id, user)
      expect(response.body).to include(I18n.l(device.last_used_at, format: :long))
      expect(response.body).to include(I18n.l(device.expires_at.to_date, format: :long))
    end
  end

  describe "GET user detail — domain profiles" do
    let(:user) { create(:user, :member, customer: customer) }
    let(:detail_path) { admin_modules_authentication_user_path(customer.id, user) }
    let(:detail_document) { Nokogiri::HTML(response.body) }
    let(:profile_fields) do
      [{ name: "Profile note", name_slug: "profile_note", html_type: "textarea" }]
    end

    def create_profile_type(name, tenant: customer, **attributes)
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", tenant).set_extendable_model!(person_model, true)
      create(:entity, customer: tenant, name: name, extended_model: person_model,
             property_schema: profile_fields.to_json, **attributes)
    end

    def create_shared_profile_type(name, **attributes)
      # Shared extension identity is not exposed by the definition writer;
      # retain the factory's real global version line for this reader fixture.
      create(:entity, :shared, name: name, property_schema: profile_fields.to_json, **attributes).tap do |entity|
        entity.update_columns(extended_model: EntityDefinitions::Capabilities::PERSON_MODEL,
                              category: Entity.categories.fetch("extension"))
      end
    end

    def create_profile_entry(entity, account: user, tenant: customer, data: {})
      create(:entity_entry, customer: tenant, entity: entity, user: account, data: data.to_json)
    end

    def profile_card(entity)
      detail_document.at_css("article[id$='-entity-#{entity.id}']")
    end
    it "shows multiple explicitly linked profiles in one domain, missing types, and Other with working destinations" do
      education = create(:entity_domain, customer: customer, name: "Education")
      health = create(:entity_domain, customer: customer, name: "Health")
      alumni = create_profile_type("Alumni")
      student = create_profile_type("Student")
      teacher = create_profile_type("Teacher")
      patient = create_profile_type("Patient")
      contact = create_profile_type("Contact")
      [student, teacher, alumni].each { |entity| education.memberships.create!(customer: customer, entity: entity) }
      health.memberships.create!(customer: customer, entity: patient)
      alumni_entry = create_profile_entry(alumni, account: nil, data: { profile_note: "Graduated with honours" })
      student_entry = create_profile_entry(student, account: nil, data: { profile_note: "Enrolled this semester" })
      contact_entry = create_profile_entry(contact, data: { profile_note: "Preferred contact profile" })

      [alumni_entry, student_entry].each do |entry|
        post admin_entity_entry_person_link_path(customer.id, entry.entity, entry), params: { user_id: user.id }
        expect(response).to redirect_to(admin_entity_entry_path(customer.id, entry.entity, entry))
      end
      get detail_path

      expect(response).to have_http_status(:ok)
      sections = detail_document.css("#user-#{user.id}-profiles > section")
      aggregate_failures do
        expect(sections.map { |section| section.at_css("h3").text }).to eq([
          "Education", "Health", I18n.t("admin_misc.domains.directory.ungrouped")
        ])
        expect(sections.first.css("h4").map(&:text)).to eq(%w[Alumni Student Teacher])
        expect(detail_document.text).not_to match(%r{\d+/\d+ linked})
        [[alumni, alumni_entry], [student, student_entry]].each do |entity, entry|
          card = profile_card(entity)
          expect(card.css("dd").map(&:text)).to include(entry.data_json.fetch("profile_note"))
          expect(card.at_css("a")["href"]).to eq(admin_entity_entry_path(customer.id, entity, entry))
        end
        contact_card = profile_card(contact)
        expect(contact_card.css("dd").map(&:text)).to include(contact_entry.data_json.fetch("profile_note"))
        expect(contact_card.at_css("h4")["class"]).to include("sr-only")
        expect(contact_card.css("a")).to be_empty
        [teacher, patient].each do |entity|
          card = profile_card(entity)
          expect(card.text).to include(I18n.t("admin_modules.users.show.profiles.create_description", entity: entity.display_label))
          expect(card.at_css("form")["action"]).to eq(admin_modules_authentication_user_profiles_path(customer.id, user, entity_id: entity.id))
          expect(card.css("a, dl")).to be_empty
        end
      end

      get profile_card(student).at_css("a")["href"]
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Enrolled this semester")
    end

    it "does not infer a profile from matching identity data, account references, or another user's entry" do
      entity = create_profile_type("Student", property_schema: (profile_fields + [
        { name: "Account reference", name_slug: "account_reference", html_type: "text" }
      ]).to_json)
      matching_data = { email: user.email, first_name: user.first_name, last_name: user.last_name,
                        account_reference: user.id, profile_note: "Unlinked matching identity" }
      unlinked = create_profile_entry(entity, account: nil, data: matching_data)
      another_user = create(:user, :member, customer: customer)
      unrelated = create_profile_entry(entity, account: another_user,
                                      data: matching_data.merge(profile_note: "Another account's private profile"))

      get detail_path

      expect(response).to have_http_status(:ok)
      card = profile_card(entity)
      aggregate_failures do
        expect(card.text).to include(I18n.t("admin_modules.users.show.profiles.create_description", entity: entity.display_label))
        expect(card.text).not_to include(I18n.t("comp_admin.person_link.badge_not_linked"))
        expect(card.at_css("form")["action"]).to eq(admin_modules_authentication_user_profiles_path(customer.id, user, entity_id: entity.id))
        expect(card.css("a, dd")).to be_empty
        expect(detail_document.text).not_to include("Unlinked matching identity", "Another account's private profile")
        expect(response.body).not_to include(admin_entity_entry_path(customer.id, entity, unlinked),
                                            admin_entity_entry_path(customer.id, entity, unrelated))
      end
    end

    it "excludes foreign definitions, domains, and shared-entry data even with a stale cross-tenant account link" do
      other_customer = create(:customer)
      other_user = create(:user, :member, customer: other_customer)
      foreign_domain = create(:entity_domain, customer: other_customer, name: "Foreign domain secret")
      foreign_type = create_profile_type("Foreign profile type", tenant: other_customer)
      foreign_domain.memberships.create!(customer: other_customer, entity: foreign_type)
      create_profile_entry(foreign_type, account: other_user, tenant: other_customer,
                           data: { profile_note: "Foreign tenant profile secret" })
      shared = create_shared_profile_type("Shared profile")
      foreign_domain.memberships.create!(customer: other_customer, entity: shared)
      foreign_entry = create_profile_entry(shared, account: other_user, tenant: other_customer,
                                           data: { profile_note: "Foreign shared entry secret" })
      # Simulate a stale imported link: tenant scoping must still protect its data.
      foreign_entry.update_column(:user_id, user.id)
      local = create_profile_type("Local profile")
      local_entry = create_profile_entry(local, data: { profile_note: "This user's tenant profile" })

      get detail_path

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(detail_document.css("#user-#{user.id}-profiles h4").map(&:text)).to eq(["Local profile", "Shared profile"])
        expect(profile_card(local).at_css("a")["href"]).to eq(admin_entity_entry_path(customer.id, local, local_entry))
        expect(profile_card(shared).text).to include(I18n.t("admin_modules.users.show.profiles.create_description", entity: shared.display_label))
        expect(profile_card(shared).text).not_to include(I18n.t("comp_admin.person_link.badge_not_linked"))
        expect(response.body).not_to include("Foreign domain secret", "Foreign profile type", "Foreign tenant profile secret",
                                            "Foreign shared entry secret", admin_entity_entry_path(customer.id, shared, foreign_entry))
      end
    end

    it "retains an inactive account's active profile while omitting inactive, deleted, and non-person definitions" do
      active = create_profile_type("Active profile")
      inactive = create_profile_type("Inactive profile", status: :inactive)
      deleted = create_profile_type("Deleted profile")
      plain = create(:entity, customer: customer, name: "Non-person records", property_schema: profile_fields.to_json)
      [active, inactive, deleted, plain].each do |entity|
        create_profile_entry(entity, data: { profile_note: "#{entity.name} content" })
      end
      deleted.soft_delete
      user.update!(status: :inactive)

      get detail_path

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(detail_document.css("#user-#{user.id}-profiles h4").map(&:text)).to eq(["Active profile"])
        expect(profile_card(active).text).to include("Active profile content")
        expect(profile_card(active).text).not_to include(I18n.t("comp_admin.person_link.badge_linked"))
        expect(response.body).not_to include("Inactive profile content", "Deleted profile content", "Non-person records content")
      end
    end

    it "renders the URL tenant's shared override and tenant-scoped links when the platform owner visits another tenant" do
      owner = find_or_create_platform_owner
      field = { name: "Mode", name_slug: "mode", html_type: "select",
                config: { options: [{ value: "remote", label: "Global option label" }] } }
      shared = create_shared_profile_type("Shared student", property_schema: [field].to_json)
      tenant_domain = create(:entity_domain, customer: customer, name: "URL tenant domain")
      tenant_domain.memberships.create!(customer: customer, entity: shared)
      owner_domain = create(:entity_domain, customer: owner.customer, name: "Owner home domain")
      owner_domain.memberships.create!(customer: owner.customer, entity: shared)
      [customer, owner.customer].each do |tenant|
        Current.set(customer: tenant, shared_resources_mode: false) do
          definition = Entity.find(shared.id)
          prefix = tenant == customer ? "URL tenant" : "Owner home"
          definition.attribute_groups_json = [
            { id: "details", name: "#{prefix} details" }, { id: "hidden", name: "Hidden-only group" }
          ]
          definition.property_schema_json = [
            field.deep_stringify_keys.deep_merge("display_label" => "#{prefix} mode", "group_id" => "details",
              "config" => { "options" => [{ "value" => "remote", "label" => "#{prefix} option label" }] }),
            { name: "Member-only notes", name_slug: "secret", html_type: "textarea", group_id: "hidden",
              visibility: { admin: false, member: true, public: false } }
          ]
          definition.save!(validate: false)
        end
      end
      shared_entry = Current.set(customer: customer, shared_resources_mode: false) do
        create_profile_entry(Entity.find(shared.id), data: { mode: "remote", secret: "Hidden tenant value" })
      end
      create_profile_entry(shared, account: owner, tenant: owner.customer, data: { mode: "remote" })
      missing = create_profile_type("Missing tenant profile")
      sign_in owner

      get detail_path

      expect(response).to have_http_status(:ok)
      card = profile_card(shared)
      aggregate_failures do
        expect(detail_document.css("#user-#{user.id}-profiles h3").map(&:text)).to eq([
          "URL tenant domain", I18n.t("admin_misc.domains.directory.ungrouped")
        ])
        expect(card.css("h5").map(&:text)).to eq(["URL tenant details"])
        expect(card.css("dt").map(&:text)).to eq(["URL tenant mode"])
        expect(card.css("dd").map(&:text)).to eq(["URL tenant option label"])
        expect(profile_card(missing).at_css("form")["action"])
          .to eq(admin_modules_authentication_user_profiles_path(customer.id, user, entity_id: missing.id))
        expect(detail_document.css("#user-#{user.id}-profiles a").map { |link| link["href"] }).to all(start_with("/#{customer.id}/admin/"))
        expect(response.body).not_to include("Global option label", "Owner home domain", "Owner home details", "Owner home option label",
                                            "Member-only notes", "Hidden-only group", "Hidden tenant value")
      end

      entry_link = detail_document.at_css("a[data-domain-entry-link='#{shared.id}']")
      expect(entry_link["href"]).to eq(admin_entity_entry_path(customer.id, shared, shared_entry))
      get entry_link["href"]
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("URL tenant option label")
    end

    it "keeps a linked profile with only admin-hidden fields distinct from a missing profile without leaking its values" do
      entity = create_profile_type("Member-private profile", property_schema: [
        { name: "Private field label", name_slug: "secret", html_type: "textarea",
          visibility: { admin: false, member: true, public: false } }
      ].to_json)
      entry = create_profile_entry(entity, data: { secret: "Private field value" })

      get detail_path

      expect(response).to have_http_status(:ok)
      card = profile_card(entity)
      aggregate_failures do
        expect(card.text).to include(I18n.t("admin_modules.users.show.profiles.no_fields"))
        expect(card.text).not_to include(I18n.t("comp_admin.person_link.badge_linked"))
        expect(card.text).not_to include(I18n.t("comp_admin.person_link.badge_not_linked"))
        expect(card.at_css("a")).to be_nil
        expect(response.body).not_to include("Private field label", "Private field value")
      end
    end

    it "rejects an admin of another tenant at this tenant's user URL without exposing profile data" do
      entity = create_profile_type("Protected tenant profile")
      create_profile_entry(entity, data: { profile_note: "Protected profile value" })
      foreign_admin = create(:user, :admin, customer: create(:customer))
      sign_in foreign_admin

      get detail_path

      aggregate_failures do
        expect(response).to redirect_to(Authentication::LandingPath.for(foreign_admin))
        expect(response.body).not_to include(user.email, "Protected tenant profile", "Protected profile value")
      end
    end

    it "shows a linked profile's association rows with links to the associated records" do
      course = create(:entity, customer: customer, name: "Course", display_label: "Course",
                               property_schema: [{ name: "Title", name_slug: "title", html_type: "text" }].to_json)
      student = create_profile_type("Student")
      student.associations_json = [{ "target_entity_id" => course.id, "target_entity_name" => course.name,
                                     "display_field" => "title", "display_field_label" => "Title",
                                     "additional_attributes" => [{ "name" => "Score", "name_slug" => "score", "html_type" => "number" }] }]
      student.save!
      student.sync_bridge_entities!
      bridge = Entity.find_by!(name: "assoc_student_course", customer_id: customer.id)
      entry = create_profile_entry(student, data: { profile_note: "Enrolled" })
      algebra = create(:entity_entry, customer: customer, entity: course, data: { title: "Algebra" }.to_json)
      create(:entity_entry, customer: customer, entity: bridge,
                            data: { student: entry.id.to_s, course: algebra.id.to_s, score: 91 }.to_json)

      get detail_path

      expect(response).to have_http_status(:ok)
      rows = profile_card(student).at_css("section[id$='-association-#{bridge.id}']")
      aggregate_failures do
        expect(rows.at_css("h5").text).to eq("Course")
        expect(rows.at_css("li a").text).to eq("Algebra")
        expect(rows.at_css("li a")["href"]).to eq(admin_entity_entry_path(customer.id, course, algebra))
        expect(rows.css("dd").map { |node| node.text.strip }).to include("91")
        add = rows.at_css("a[data-action='association-dialog#open']")
        expect(add["href"]).to eq(new_admin_entity_entry_association_entry_path(customer.id, student, entry, bridge.id))
        expect(add.text.squish).to eq(I18n.t("admin_misc.entities.association_entries.new_title", name: "Course"))
        enrollment = EntityEntry.find_by!(entity_id: bridge.id, customer_id: customer.id)
        return_to = admin_modules_authentication_user_path(customer.id, user, anchor: rows["id"])
        edit = rows.at_css("a[href*='/edit']")
        expect(edit["data-action"]).to eq("association-dialog#open")
        expect(Rack::Utils.parse_query(URI.parse(edit["href"]).query)["return_to"]).to eq(return_to)
        expect(edit["href"]).to start_with(edit_admin_entity_entry_association_entry_path(customer.id, student, entry, bridge.id, enrollment))
        destroy = rows.at_css("a[data-turbo-method='delete']")
        expect(destroy["data-turbo-confirm"]).to eq(I18n.t("admin_misc.entities.association_entries.delete_confirm"))
        expect(Rack::Utils.parse_query(URI.parse(destroy["href"]).query)["return_to"]).to eq(return_to)
        expect(Nokogiri::HTML(response.body).css("dialog#entity-quick-add-dialog-0").size).to eq(1)
      end
    end
  end

  describe "POST /:customer_id/admin/modules/authentication/users/:user_id/profiles" do
    let(:user) { create(:user, :member, customer: customer) }
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:entity) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: "Student", extended_model: person_model, property_schema: [
        { name: "Student number", name_slug: "student_number", html_type: "text", validators: [{ type: "presence" }] },
        { name: "Major", name_slug: "major", html_type: "text" }
      ].to_json)
    end
    let(:profiles_path) { admin_modules_authentication_user_profiles_path(customer.id, user, entity_id: entity.id) }
    let(:valid_params) { { entry: { data: { student_number: "S-100", major: "History" } } } }
    let(:entries) { EntityEntry.where(customer_id: customer.id, entity_id: entity.id) }

    describe "auth guards" do
      let(:guard_path) { profiles_path }

      it_behaves_like "an admin-guarded request", :post
    end

    it "creates the entry, links it to the user, audits the link, and shows it on the user page" do
      allow(Authentication::AuditLog).to receive(:record).and_call_original

      expect { post profiles_path, params: valid_params }.to change(entries, :count).by(1)

      entry = entries.sole
      aggregate_failures do
        expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, user))
        expect(response).to have_http_status(:see_other)
        expect(flash[:notice]).to eq(I18n.t("admin_modules.flash.users.profile_created", entity: entity.display_label))
        expect(entry.user_id).to eq(user.id)
        expect(entry.data_json).to include("student_number" => "S-100", "major" => "History")
        expect(Authentication::AuditLog).to have_received(:record)
          .with(hash_including(event: "person.linked", user: admin, entry_id: entry.id, linked_user_id: user.id))
      end

      follow_redirect!
      card = Nokogiri::HTML(response.body).at_css("article[id$='-entity-#{entity.id}']")
      expect(card.text).to include("S-100", "History")
      expect(card.text).not_to include(I18n.t("comp_admin.person_link.badge_linked"))
      expect(card.at_css("form")).to be_nil
    end

    it "re-renders the user page with errors and the submitted values, creating nothing, when validation fails" do
      expect { post profiles_path, params: { entry: { data: { student_number: "", major: "History" } } } }
        .not_to change(EntityEntry, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      card = Nokogiri::HTML(response.body).at_css("article[id$='-entity-#{entity.id}']")
      aggregate_failures do
        expect(card.at_css("[role='alert']")).to be_present
        expect(card.at_css("input[name='entry[data][major]']")["value"]).to eq("History")
        expect(response.body).to include(user.email)
      end
    end

    it "rolls back the new entry when the link fails because the account is inactive" do
      user.update!(status: :inactive)

      expect { post profiles_path, params: valid_params }.not_to change(EntityEntry, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.users.show.profiles.inactive_description", entity: entity.display_label))
    end

    it "refuses a second profile of the same type and returns to the user page showing the existing one" do
      create(:entity_entry, customer: customer, entity: entity, user: user, data: { student_number: "S-1" }.to_json)

      expect { post profiles_path, params: valid_params }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, user))
      expect(flash[:alert]).to eq(I18n.t("people.errors.user_already_linked"))
    end

    it "404s for another tenant's user, a non-person entity, or another tenant's entity" do
      foreign = create(:customer)
      enable_module!("authentication", foreign).set_extendable_model!(person_model, true)
      foreign_entity = create(:entity, customer: foreign, name: "Foreign", extended_model: person_model)
      plain = create(:entity, customer: customer, name: "Course")
      [
        admin_modules_authentication_user_profiles_path(customer.id, create(:user, :member, customer: foreign), entity_id: entity.id),
        admin_modules_authentication_user_profiles_path(customer.id, user, entity_id: plain.id),
        admin_modules_authentication_user_profiles_path(customer.id, user, entity_id: foreign_entity.id)
      ].each do |path|
        # A 404 exception response does not write the session cookie.
        sign_in admin
        expect { post path, params: valid_params }.not_to change(EntityEntry, :count)
        expect(response).to have_http_status(:not_found), path
      end
    end

    it "rejects an admin of another tenant" do
      sign_in create(:user, :admin, customer: create(:customer))

      expect { post profiles_path, params: valid_params }.not_to change(EntityEntry, :count)
      expect(response).not_to have_http_status(:see_other)
      expect(entries.where(user_id: user.id)).to be_empty
    end

    it "rejects a payload without entry data" do
      post profiles_path, params: { entry: { other: "x" } }

      expect(response).to have_http_status(:bad_request)
    end
  end

  # ==========================================================================
  # GET /admin/users/new
  # ==========================================================================

  describe "GET /:customer_id/admin/users/new" do
    it "renders new user form" do
      get new_admin_modules_authentication_user_path(customer.id)
      expect(response.body).to include(I18n.t("admin_modules.users.new.title"))
      %w[account password access].each do |section|
        expect(response.body).to include(I18n.t("admin_modules.users.form.sections.#{section}"))
      end
      expect(response.body).to include(I18n.t("admin_modules.users.form.role_hint.member"))
    end
  end

  # ==========================================================================
  # POST /admin/users
  # ==========================================================================

  describe "POST /:customer_id/admin/users" do
    # Controller requires :authentication_user (not :user) as the params key
    let(:valid_params) do
      {
        authentication_user: {
          first_name: "New",
          last_name: "User",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123",
          role: "member"
        }
      }
    end

    it "creates a new user" do
      expect {
        post users_index_path, params: valid_params
      }.to change(Authentication::User, :count).by(1)
    end

    it "defaults a new account to exactly one member assignment when role is omitted" do
      payload = valid_params.deep_dup
      payload[:authentication_user].delete(:role)

      post users_index_path, params: payload

      expect(response).to redirect_to(users_index_path)
      user = Authentication::User.find_by!(email: payload[:authentication_user][:email])
      expect(user.reserved_role_keys).to eq(["member"])
      expect(user.users_roles.joins(:role).where(roles: { system: true, key: Authentication::User::RESERVED_ROLE_KEYS }).count).to eq(1)
    end

    it "confirms the user so they can sign in without an email confirmation" do
      post users_index_path, params: valid_params
      new_user = Authentication::User.find_by(email: "newuser@example.com")
      expect(new_user.confirmed_at).to be_present
    end

    it "assigns the user to the current tenant" do
      post users_index_path, params: valid_params
      new_user = Authentication::User.find_by(email: "newuser@example.com")
      expect(new_user.customer_id).to eq(customer.id)
    end

    it "redirects to users list on success" do
      post users_index_path, params: valid_params
      expect(response).to redirect_to(users_index_path)
    end

    it "does not create a user when the submitted role is owner and the account is ineligible" do
      expect {
        post users_index_path, params: valid_params.deep_merge(
          authentication_user: { email: "not-owner@example.com", role: "owner" }
        )
      }.not_to change(Authentication::User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "renders form with errors for invalid params" do
      post users_index_path, params: { authentication_user: { first_name: "", email: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "prevents duplicate emails within the same tenant" do
      create(:user, customer: customer, email: "duplicate@example.com")
      post users_index_path, params: valid_params.deep_merge(authentication_user: { email: "duplicate@example.com" })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ==========================================================================
  # GET /admin/users/:id/edit
  # ==========================================================================

  describe "GET /:customer_id/admin/users/:id/edit" do
    let!(:user) { create(:user, customer: customer) }

    it "renders edit form" do
      get edit_admin_modules_authentication_user_path(customer.id, user)
      expect(response.body).to include("Edit User")
    end
  end

  describe "user form population" do
    let(:form_user) do
      create(:user, :member, customer: customer,
             first_name: '李 "Alice" <b>林</b>', last_name: "D'Arcy & 王",
             email: "target+prefill@example.com", password: "password123")
    end
    let(:edit_path) { edit_admin_modules_authentication_user_path(customer.id, form_user) }
    let(:update_path) { admin_modules_authentication_user_path(customer.id, form_user) }
    let(:form_document) { Nokogiri::HTML(response.body) }

    def user_form_field(name)
      form_document.at_css("[name='authentication_user[#{name}]']")
    end

    def selected_user_roles
      user_form_field(:role).css("option[selected]").map { |option| option["value"] }
    end

    it "prefills the persisted identity while escaping Unicode names containing HTML" do
      get edit_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(user_form_field(:first_name)["value"]).to eq(form_user.first_name)
        expect(user_form_field(:last_name)["value"]).to eq(form_user.last_name)
        expect(user_form_field(:email)["value"]).to eq(form_user.email)
        expect(response.body).to include("李 &quot;Alice&quot; &lt;b&gt;林&lt;/b&gt;", "D&#39;Arcy &amp; 王")
        expect(form_document.css("b").map(&:text)).not_to include("林")
      end
    end

    it "explicitly selects the persisted member role" do
      get edit_path

      expect(response).to have_http_status(:ok)
      expect(selected_user_roles).to eq(["member"])
    end

    it "explicitly selects the persisted admin role" do
      target = create(:user, :admin, customer: customer)

      get edit_admin_modules_authentication_user_path(customer.id, target)

      expect(response).to have_http_status(:ok)
      expect(selected_user_roles).to eq(["admin"])
    end

    it "explicitly selects owner for the pinned platform-owner account" do
      owner = find_or_create_platform_owner
      ensure_customer_feature_module(owner.customer, auth_module, status: :active)
      sign_in owner

      get edit_admin_modules_authentication_user_path(owner.customer_id, owner)

      expect(response).to have_http_status(:ok)
      expect(selected_user_roles).to eq(["owner"])
    end

    it "leaves both password controls empty when editing a persisted account" do
      get edit_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        %i[password password_confirmation].each do |name|
          expect(user_form_field(name)["type"]).to eq("password")
          expect(user_form_field(name)["value"].to_s).to eq("")
        end
        expect(response.body).not_to include("password123", form_user.encrypted_password)
      end
    end

    it "defaults a new form to member with empty identity and password controls" do
      get new_admin_modules_authentication_user_path(customer.id)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(selected_user_roles).to eq(["member"])
        %i[first_name last_name email password password_confirmation].each do |name|
          expect(user_form_field(name)["value"].to_s).to eq("")
        end
      end
    end

    it "retains the attempted identity and submitted admin role on an invalid create" do
      attempted = {
        first_name: '赵 "New" <b>名</b>', last_name: "", email: "invalid+attempt",
        password: "newpassword123", password_confirmation: "newpassword123", role: "admin"
      }

      expect {
        post users_index_path, params: { authentication_user: attempted }
      }.not_to change(Authentication::User, :count)

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        %i[first_name last_name email].each do |name|
          expect(user_form_field(name)["value"].to_s).to eq(attempted.fetch(name))
        end
        expect(selected_user_roles).to eq(["admin"])
        expect(response.body).to include("赵 &quot;New&quot; &lt;b&gt;名&lt;/b&gt;")
        %i[password password_confirmation].each do |name|
          expect(user_form_field(name)["value"].to_s).to eq("")
        end
      end
    end

    it "retains a deliberately cleared name and submitted admin role on an invalid update without persisting them" do
      original = form_user.attributes.slice("first_name", "last_name", "email", "encrypted_password")
      attempted = {
        first_name: "", last_name: '赵 "Changed" <b>姓</b>', email: "invalid+attempt",
        password: "newpassword123", password_confirmation: "newpassword123", role: "admin"
      }

      patch update_path, params: { authentication_user: attempted }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        %i[first_name last_name email].each do |name|
          expect(user_form_field(name)["value"].to_s).to eq(attempted.fetch(name))
        end
        expect(selected_user_roles).to eq(["admin"])
        expect(response.body).to include("赵 &quot;Changed&quot; &lt;b&gt;姓&lt;/b&gt;")
        %i[password password_confirmation].each do |name|
          expect(user_form_field(name)["value"].to_s).to eq("")
        end
        expect(form_user.reload.attributes.slice(*original.keys)).to eq(original)
        expect(form_user.reserved_role_keys).to eq(["member"])
      end
    end

    it "falls back to the persisted admin role when role is omitted from an invalid update" do
      target = create(:user, :admin, customer: customer)
      original = target.attributes.slice("first_name", "last_name", "email", "encrypted_password")

      patch admin_modules_authentication_user_path(customer.id, target),
            params: { authentication_user: { first_name: "Attempted", email: "" } }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        expect(user_form_field(:first_name)["value"]).to eq("Attempted")
        expect(user_form_field(:email)["value"].to_s).to eq("")
        expect(selected_user_roles).to eq(["admin"])
        expect(target.reload.attributes.slice(*original.keys)).to eq(original)
        expect(target.reserved_role_keys).to eq(["admin"])
      end
    end

    it "accepts an unchanged edit-form submission without changing the member role or password" do
      original = form_user.attributes.slice("first_name", "last_name", "email", "encrypted_password")
      get edit_path
      expect(response).to have_http_status(:ok)

      submitted = %i[first_name last_name email password password_confirmation].to_h do |name|
        [name, user_form_field(name)["value"].to_s]
      end
      # A browser submits the first option if the form has no explicit selection.
      role_select = user_form_field(:role)
      submitted[:role] = (role_select.at_css("option[selected]") || role_select.at_css("option"))["value"]

      patch update_path, params: { authentication_user: submitted }

      aggregate_failures do
        expect(response).to redirect_to(update_path)
        expect(form_user.reload.attributes.slice(*original.keys)).to eq(original)
        expect(form_user.reserved_role_keys).to eq(["member"])
        expect(form_user.valid_password?("password123")).to be(true)
      end
    end
  end

  # ==========================================================================
  # PATCH /admin/users/:id
  # ==========================================================================

  describe "PATCH /:customer_id/admin/users/:id" do
    let!(:user) { create(:user, customer: customer, first_name: "Original") }

    it "updates user details" do
      patch admin_modules_authentication_user_path(customer.id, user), params: { authentication_user: { first_name: "Updated" } }
      expect(user.reload.first_name).to eq("Updated")
    end

    it "redirects to user show on success" do
      patch admin_modules_authentication_user_path(customer.id, user), params: { authentication_user: { first_name: "Updated" } }
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, user))
    end

    it "updates without password when password is blank" do
      patch admin_modules_authentication_user_path(customer.id, user), params: { authentication_user: { first_name: "NoPassChange", password: "", password_confirmation: "" } }
      expect(user.reload.first_name).to eq("NoPassChange")
    end

    it "updates password when provided" do
      patch admin_modules_authentication_user_path(customer.id, user), params: { authentication_user: { password: "newpassword123", password_confirmation: "newpassword123" } }
      expect(user.reload.valid_password?("newpassword123")).to be true
    end

    it "renders form with errors for invalid params" do
      patch admin_modules_authentication_user_path(customer.id, user), params: { authentication_user: { email: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ==========================================================================
  # PATCH /admin/users/:id/activate
  # ==========================================================================

  describe "PATCH /:customer_id/admin/users/:id/activate" do
    let!(:inactive_user) { create(:user, :inactive, customer: customer) }

    it "activates an inactive user" do
      post admin_modules_authentication_user_activation_path(customer.id, inactive_user)
      expect(inactive_user.reload).to be_active
    end

    it "redirects to users list" do
      post admin_modules_authentication_user_activation_path(customer.id, inactive_user)
      expect(response).to redirect_to(users_index_path)
    end
  end

  # ==========================================================================
  # PATCH /admin/users/:id/reset_mfa
  # ==========================================================================

  describe "PATCH /:customer_id/admin/users/:id/reset_mfa" do
    let!(:mfa_user) { create(:user, customer: customer, otp_secret: ROTP::Base32.random, otp_required_for_login: true) }

    it "resets MFA for a user with MFA enabled" do
      post admin_modules_authentication_user_mfa_reset_path(customer.id, mfa_user)
      mfa_user.reload
      expect(mfa_user.otp_secret).to be_nil
      expect(mfa_user.otp_required_for_login).to be false
    end

    it "resets MFA for a user with MFA configured but not enabled" do
      configured_user = create(:user, customer: customer, otp_secret: ROTP::Base32.random, otp_required_for_login: false)
      post admin_modules_authentication_user_mfa_reset_path(customer.id, configured_user)
      configured_user.reload
      expect(configured_user.otp_secret).to be_nil
      expect(configured_user.otp_required_for_login).to be false
    end

    it "redirects to user show with success notice" do
      post admin_modules_authentication_user_mfa_reset_path(customer.id, mfa_user)
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, mfa_user))
      expect(flash[:notice]).to include("MFA has been reset")
    end

    it "redirects with alert when MFA is not configured" do
      plain_user = create(:user, customer: customer)
      post admin_modules_authentication_user_mfa_reset_path(customer.id, plain_user)
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, plain_user))
      expect(flash[:alert]).to include("MFA is not configured")
    end
  end

  # ==========================================================================
  # PATCH /admin/users/:id/deactivate
  # ==========================================================================

  describe "PATCH /:customer_id/admin/users/:id/deactivate" do
    let!(:target_user) { create(:user, customer: customer) }

    it "deactivates a user" do
      delete admin_modules_authentication_user_activation_path(customer.id, target_user)
      expect(target_user.reload).to be_inactive
    end

    it "redirects to users list" do
      delete admin_modules_authentication_user_activation_path(customer.id, target_user)
      expect(response).to redirect_to(users_index_path)
    end

    it "prevents deactivating yourself" do
      delete admin_modules_authentication_user_activation_path(customer.id, admin_user)
      expect(admin_user.reload).to be_active
      expect(response).to redirect_to(users_index_path)
      expect(flash[:alert]).to include("cannot deactivate your own account")
    end
  end

  # ==========================================================================
  # DELETE /admin/users/:id — move to trash
  # ==========================================================================

  describe "DELETE /:customer_id/admin/users/:id" do
    let!(:target_user) { create(:user, :member, customer: customer, first_name: "Nora", last_name: "Trash") }

    it "moves the user to trash and hides them from the directory" do
      delete admin_modules_authentication_user_path(customer.id, target_user)

      expect(target_user.reload).to be_trashed
      expect(response).to redirect_to(users_index_path)
      expect(flash[:notice]).to eq(I18n.t("admin_modules.flash.users.trashed", name: target_user.display_name))

      get users_index_path
      expect(response.body).not_to include(target_user.email)
      expect(response.body).not_to include(admin_modules_authentication_user_path(customer.id, target_user))

      get trash_admin_modules_authentication_users_path(customer.id)
      expect(response.body).to include(target_user.email)
      expect(response.body).to include(I18n.t("common.status.trashed"))
    end

    it "does not move your own account to trash" do
      delete admin_modules_authentication_user_path(customer.id, admin_user)

      expect(admin_user.reload).to be_active
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, admin_user))
      expect(flash[:alert]).to eq(I18n.t("admin_modules.flash.users.trash_self_blocked"))
    end

    it "restores a trashed user to the directory" do
      target_user.update!(status: :trashed)

      patch restore_admin_modules_authentication_user_path(customer.id, target_user)

      expect(target_user.reload).to be_active
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, target_user))
      expect(flash[:notice]).to eq(I18n.t("admin_modules.flash.users.restored", name: target_user.display_name))

      get users_index_path
      expect(response.body).to include(target_user.email)
    end

    it "does not trash a user from another tenant" do
      foreign = create(:user, :member, customer: create(:customer), first_name: "Foreign")

      delete admin_modules_authentication_user_path(customer.id, foreign)

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload).to be_active
    end
  end

  # ==========================================================================
  # Cross-tenant isolation
  # ==========================================================================

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_user) { create(:user, customer: other_customer) }

    before { ensure_customer_feature_module(other_customer, auth_module, status: :active) }

    it "cannot show a user from another tenant (404)" do
      get admin_modules_authentication_user_path(customer.id, other_user)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot edit a user from another tenant (404)" do
      get edit_admin_modules_authentication_user_path(customer.id, other_user)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot update a user from another tenant (404)" do
      patch admin_modules_authentication_user_path(customer.id, other_user),
            params: { authentication_user: { first_name: "Hijack" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ==========================================================================
  # Index badge lambda branches — MFA state coverage
  # ==========================================================================

  describe "index MFA badge variants" do
    it "renders 'Enabled' badge for a user with otp_required_for_login" do
      create(:user, :member, :with_mfa, customer: customer)
      get users_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Enabled")
    end

    it "renders 'Configured' badge for a user with otp_secret but login not required" do
      create(:user, :member, :mfa_configured, customer: customer)
      get users_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Configured")
    end

    it "renders 'Off' badge for a user with no MFA configured" do
      create(:user, :member, customer: customer)
      get users_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Off")
    end
  end

  # ==========================================================================
  # assign_user_role branches
  # ==========================================================================

  describe "assign_user_role branch coverage" do
    let!(:target_user) { create(:user, customer: customer, first_name: "Target") }

    it "does nothing when role param is blank" do
      # role_key.blank? → early return, roles unchanged
      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: "NoRole", role: "" } }
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, target_user))
    end

    it "assigns admin role and clears previous system roles" do
      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "admin" } }
      expect(response).to be_redirect
      expect(target_user.reload.admin?).to be(true)
    end

    it "keeps the existing role and profile when updating the reserved join fails" do
      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "admin" } }
      expect(target_user.reload.admin?).to be(true)

      reserved_join = target_user.users_roles.joins(:role).find_by!(roles: { system: true, key: "admin" })
      allow_any_instance_of(UsersRole).to receive(:update!).and_wrap_original do |method, *args|
        if method.receiver.id == reserved_join.id
          raise ActiveRecord::RecordInvalid.new(method.receiver)
        end
        method.call(*args)
      end

      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: "KeptAdmin", role: "member" } }

      expect(response).to have_http_status(:unprocessable_content)
      fresh = ::Authentication::User.find(target_user.id)
      expect(fresh.admin?).to be(true)
      expect(fresh.member?).to be(false)
      expect(fresh.first_name).to eq(target_user.first_name)
      expect(response.body).to include(I18n.t("admin_modules.flash.users.invalid_role"))
    end

    it "replaces the admin assignment in place with exactly one member assignment" do
      # First make target_user an admin, then demote to member. Demoting to
      # "member" must leave the user with a real member role row — otherwise the
      # user passes neither the member nor the admin RouteAuthorization gate and
      # is locked out of every tenant surface (regression guard for the
      # member-role lockout bug).
      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "admin" } }
      expect(::Authentication::User.find(target_user.id).admin?).to be(true)
      reserved_join_id = target_user.users_roles.joins(:role).find_by!(roles: { system: true, key: "admin" }).id

      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "member" } }
      expect(response).to be_redirect

      fresh = ::Authentication::User.find(target_user.id)
      expect(fresh.admin?).to be(false)
      expect(fresh.owner?).to be(false)
      # The member role row IS created, so the user is not locked out.
      expect(fresh.member?).to be(true)
      expect(fresh.users_roles.joins(:role).where(roles: { system: true, key: "member" }).count).to eq(1)
      expect(fresh.users_roles.find(reserved_join_id).role.key).to eq("member")
    end

    it "preserves existing supplemental roles while replacing the reserved join" do
      member = create(:user, :member, customer: customer)
      supplemental_role = create(:role, customer: customer, key: "legacy_access", name: "Legacy access")
      member.users_roles.create!(role: supplemental_role)
      reserved_join = member.users_roles.joins(:role).find_by!(roles: { system: true, key: "member" })

      patch admin_modules_authentication_user_path(customer.id, member),
            params: { authentication_user: { first_name: "Promoted", role: "admin" } }

      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, member))
      expect(member.reload.first_name).to eq("Promoted")
      expect(member.roles.pluck(:key)).to match_array(["admin", "legacy_access"])
      expect(reserved_join.reload.role.key).to eq("admin")
    end

    it "does not strip existing roles when the requested role key is unknown" do
      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "admin" } }
      expect(target_user.reload.admin?).to be(true)

      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "not_a_role" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(target_user.reload.admin?).to be(true)
    end

    it "creates the per-customer member role on first demotion when it does not yet exist" do
      customer.roles.where(key: "member").destroy_all

      patch admin_modules_authentication_user_path(customer.id, target_user),
            params: { authentication_user: { first_name: target_user.first_name, role: "member" } }
      expect(response).to be_redirect

      expect(customer.roles.exists?(key: "member", system: true)).to be(true)
      expect(::Authentication::User.find(target_user.id).member?).to be(true)
    end

    context "when current_user is an owner and target is also owner" do
      it "owner can update another owner's name without stripping their role" do
        # Platform owner updating themselves (owner? && current_user.owner? → proceeds)
        platform_owner = find_or_create_platform_owner
        sign_in platform_owner
        patch admin_modules_authentication_user_path(platform_owner.customer_id, platform_owner),
              params: { authentication_user: { first_name: "StillOwner", role: "owner" } }
        # role_key == "owner" but eligible_for_owner_role? is true → should not be blocked
        expect(platform_owner.reload.owner?).to be(true)
      end

      it "rejects owner self-demotion and rolls back the accompanying profile update" do
        platform_owner = find_or_create_platform_owner
        sign_in platform_owner
        original_name = platform_owner.first_name
        owner_join_id = platform_owner.users_roles.joins(:role).find_by!(roles: { system: true, key: "owner" }).id

        patch admin_modules_authentication_user_path(platform_owner.customer_id, platform_owner),
              params: { authentication_user: { first_name: "RejectedDemotion", role: "member" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(I18n.t("admin_settings.errors.validations.role_owner_reserved"))
        expect(platform_owner.reload.first_name).to eq(original_name)
        expect(platform_owner.owner?).to be(true)
        expect(UsersRole.find(owner_join_id).role.key).to eq("owner")
      end
    end

    context "when a non-owner tries to edit the platform owner's role" do
      it "cannot strip the platform owner's role (user.owner? && !current_user.owner? guard)" do
        platform_owner = find_or_create_platform_owner
        # admin_user is scoped to customer (not owner), trying to update platform_owner
        # Platform owner is in a different customer; find_user scopes to current_customer_id → 404
        get admin_modules_authentication_user_path(customer.id, platform_owner)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ==========================================================================
  # Owner-account protection (S1) — the owner-pin protects the owner ROLE;
  # this guards the owner ACCOUNT from a co-tenant non-owner admin.
  # ==========================================================================

  describe "owner-account protection" do
    let(:platform_customer) { ensure_platform_customer }
    let(:platform_owner)    { find_or_create_platform_owner }
    # A non-owner admin sitting inside the platform-owner customer (81721200).
    let(:co_tenant_admin)   { create(:user, :admin, customer: platform_customer, password: "password123") }

    before do
      ensure_customer_feature_module(platform_customer, auth_module, status: :active)
      platform_owner.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      sign_in co_tenant_admin
    end

    it "blocks a non-owner admin from resetting the owner's MFA" do
      post admin_modules_authentication_user_mfa_reset_path(platform_customer.id, platform_owner)
      expect(response).to redirect_to(admin_modules_authentication_user_path(platform_customer.id, platform_owner))
      expect(flash[:alert]).to eq(I18n.t("admin_modules.flash.users.owner_account_protected"))
      expect(platform_owner.reload.otp_secret).to be_present
    end

    it "blocks a non-owner admin from deactivating the owner" do
      delete admin_modules_authentication_user_activation_path(platform_customer.id, platform_owner)
      expect(response).to redirect_to(admin_modules_authentication_users_path(platform_customer.id))
      expect(flash[:alert]).to eq(I18n.t("admin_modules.flash.users.owner_account_protected"))
      expect(platform_owner.reload).to be_active
    end

    it "blocks a non-owner admin from moving the owner to trash" do
      delete admin_modules_authentication_user_path(platform_customer.id, platform_owner)
      expect(response).to redirect_to(admin_modules_authentication_users_path(platform_customer.id))
      expect(flash[:alert]).to eq(I18n.t("admin_modules.flash.users.owner_account_protected"))
      expect(platform_owner.reload).not_to be_trashed
    end

    it "blocks a non-owner admin from setting the owner's password" do
      patch admin_modules_authentication_user_path(platform_customer.id, platform_owner),
            params: { authentication_user: { password: "attacker-chosen-pw", password_confirmation: "attacker-chosen-pw" } }
      expect(response).to redirect_to(admin_modules_authentication_users_path(platform_customer.id))
      expect(flash[:alert]).to eq(I18n.t("admin_modules.flash.users.owner_account_protected"))
      expect(platform_owner.reload.valid_password?("attacker-chosen-pw")).to be(false)
    end

    it "allows the owner to update the owner account (guard does not block owners)" do
      # Drop the owner's MFA so the app-wide MFA enforcer doesn't intercept the
      # request — this test isolates the owner-account guard, not MFA routing.
      platform_owner.update!(otp_required_for_login: false, otp_secret: nil)
      sign_in platform_owner
      patch admin_modules_authentication_user_path(platform_customer.id, platform_owner),
            params: { authentication_user: { first_name: "OwnerEdited" } }
      expect(platform_owner.reload.first_name).to eq("OwnerEdited")
    end
  end

  # ==========================================================================
  # Billing quota enforcement on admin user-create
  # ==========================================================================

  describe "POST /:customer_id/admin/users — member quota enforcement" do
    def enable_member_countable_item!
      Billing::CountableItem.find_or_create_by!(key: "member") do |i|
        i.label    = "Members"
        i.enabled  = true
        i.position = 4
      end.tap { |i| i.update!(enabled: true) }
    end

    def accept_member_quota(cust, limit_value)
      plan = create(:billing_plan)
      snapshot = Billing::PlanChangePolicy.snapshot(plan: plan, currency: "USD")
      snapshot["limits"]["member"] = limit_value
      create(:billing_subscription, customer: cust, plan: plan, status: "active", plan_snapshot: snapshot)
    end

    let(:quota_valid_params) do
      {
        authentication_user: {
          first_name: "Quota",
          last_name:  "User",
          email:      "quotauser@example.com",
          password:   "password123",
          password_confirmation: "password123",
          role: "member"
        }
      }
    end

    before { enable_member_countable_item! }

    context "when at the member limit" do
      before do
        create(:user, :member, customer: customer)
        accept_member_quota(customer, 1)
      end

      it "returns 422 and does not create a user" do
        expect {
          post users_index_path, params: quota_valid_params
        }.not_to change(::Authentication::User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "includes the quota message in the response body" do
        post users_index_path, params: quota_valid_params
        expect(response.body).to include("Upgrade your plan")
      end
    end

    context "when under the member limit" do
      before do
        accept_member_quota(customer, 1)
      end

      it "creates the user successfully" do
        expect(Billing::Quota.for(customer).usage("member")).to eq(0)
        expect {
          post users_index_path, params: quota_valid_params
        }.to change(::Authentication::User, :count).by(1)

        expect(response).to have_http_status(:redirect)
      end

      it "re-checks capacity under the lock after a competing member takes the last slot" do
        inserted = false
        allow_any_instance_of(Customer).to receive(:with_lock).and_wrap_original do |method, *args, **kwargs, &block|
          if method.receiver.id == customer.id && !inserted
            inserted = true
            create(:user, :member, customer: customer)
          end
          method.call(*args, **kwargs, &block)
        end

        expect {
          post users_index_path, params: quota_valid_params
        }.not_to change { ::Authentication::User.exists?(email: "quotauser@example.com") }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Billing::Quota.for(customer).usage("member")).to eq(1)
      end
    end

    context "when the plan limit is unlimited (-1)" do
      before { accept_member_quota(customer, Billing::PlanLimit::UNLIMITED) }

      it "creates the user regardless of existing count" do
        expect {
          post users_index_path, params: quota_valid_params
        }.to change(::Authentication::User, :count).by(1)

        expect(response).to have_http_status(:redirect)
      end
    end

    context "when the customer is the platform owner (customer 81721200)" do
      before { sign_in find_or_create_platform_owner }

      it "bypasses the quota check and creates the user" do
        platform_cid = ::Authentication::User::PLATFORM_CUSTOMER_ID
        # Set up a tight limit for the platform customer to prove bypass
        accept_member_quota(ensure_platform_customer, 0)

        params = {
          authentication_user: {
            first_name: "Owner",
            last_name:  "Bypass",
            email:      "ownercreate_#{SecureRandom.hex(4)}@example.com",
            password:   "password123",
            password_confirmation: "password123",
            role: "member"
          }
        }

        expect {
          post admin_modules_authentication_users_path(platform_cid), params: params
        }.to change(::Authentication::User, :count).by(1)

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  # ==========================================================================
  # Self-targeting guards (A10)
  # ==========================================================================

  describe "self-targeting guards" do
    it "prevents an admin from resetting their own MFA" do
      # Configure MFA on a *separate* mfa-enabled session so the verify path
      # is satisfied; the controller guard, not enforce_mfa!, is what we're
      # exercising.
      admin_user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      totp = ROTP::TOTP.new(admin_user.otp_secret)
      post mfa_session_path(customer.id), params: { otp_code: totp.now }

      post admin_modules_authentication_user_mfa_reset_path(customer.id, admin_user)

      admin_user.reload
      expect(admin_user.otp_secret).to be_present
      expect(admin_user.otp_required_for_login).to be(true)
      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, admin_user))
      expect(flash[:alert]).to match(/cannot reset your own MFA/i)
    end

    it "prevents a non-owner admin from elevating themselves to owner" do
      patch admin_modules_authentication_user_path(customer.id, admin_user),
            params: { authentication_user: { first_name: admin_user.first_name, role: "owner" } }

      expect(admin_user.reload.owner?).to be(false)
    end

    it "prevents a non-owner admin from elevating another user to owner" do
      member = create(:user, customer: customer)
      patch admin_modules_authentication_user_path(customer.id, member),
            params: { authentication_user: { first_name: member.first_name, role: "owner" } }

      expect(member.reload.owner?).to be(false)
    end

    it "rejects changing own email without the current password" do
      original_email = admin_user.email
      patch admin_modules_authentication_user_path(customer.id, admin_user),
            params: { authentication_user: { email: "new-admin@example.com" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(admin_user.reload.email).to eq(original_email)
    end

    it "still allows a name-only update of the signed-in admin" do
      patch admin_modules_authentication_user_path(customer.id, admin_user),
            params: { authentication_user: { first_name: "SelfRename" } }

      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, admin_user))
      expect(admin_user.reload.first_name).to eq("SelfRename")
    end
  end

  describe "role and MFA mutation audit outcomes" do
    it "records both sides of a reserved-role replacement with the acting admin" do
      target = create(:user, :member, :with_mfa, customer: customer)
      secret = target.otp_secret
      first_event_id = Authentication::Event.maximum(:id) || 0

      patch admin_modules_authentication_user_path(customer.id, target),
            params: { authentication_user: { first_name: "Promoted", role: "admin" } }

      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, target))
      events = Authentication::Event.where(user_id: target.id, event: %w[role_granted role_revoked])
                                    .where("id > ?", first_event_id).order(:id)
      expect(events.pluck(:event)).to eq(%w[role_revoked role_granted])
      events.each do |event|
        expect(event.customer_id).to eq(customer.id)
        expect(event.metadata).to include("actor_id" => admin_user.id, "source" => "role_assignment", "outcome" => "success")
        expect(event.metadata.to_json).not_to include(secret, target.encrypted_password)
      end
    end

    it "does not claim a role change when a profile edit retains the same reserved assignment" do
      target = create(:user, :member, customer: customer)

      expect {
        patch admin_modules_authentication_user_path(customer.id, target),
              params: { authentication_user: { first_name: "ProfileOnly", role: "member" } }
      }.not_to change { Authentication::Event.where(user_id: target.id, event: %w[role_granted role_revoked]).count }

      expect(target.reload.first_name).to eq("ProfileOnly")
      expect(target.member?).to be(true)
    end

    [true, false].each do |required|
      it "audits an admin reset of configured MFA with required=#{required}" do
        target = create(:user, :member, customer: customer, otp_secret: ROTP::Base32.random,
                        otp_required_for_login: required)
        secret = target.otp_secret

        expect {
          post admin_modules_authentication_user_mfa_reset_path(customer.id, target)
        }.to change { Authentication::Event.where(event: "mfa_disabled", user_id: target.id).count }.by(1)

        expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, target))
        event = Authentication::Event.where(event: "mfa_disabled", user_id: target.id).last
        expect(event.metadata).to include(
          "actor_id" => admin_user.id, "source" => "admin_reset", "outcome" => "success",
          "before" => { "required" => required, "configured" => true },
          "after" => { "required" => false, "configured" => false }
        )
        expect(event.metadata.to_json).not_to include(secret)
      end
    end

    it "does not audit a blocked self-reset" do
      expect {
        post admin_modules_authentication_user_mfa_reset_path(customer.id, admin_user)
      }.not_to change { Authentication::Event.where(event: "mfa_disabled", user_id: admin_user.id).count }

      expect(response).to redirect_to(admin_modules_authentication_user_path(customer.id, admin_user))
    end
  end
end
