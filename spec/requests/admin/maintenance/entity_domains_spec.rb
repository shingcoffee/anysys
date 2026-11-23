# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin maintenance entity domains", type: :request do
  let(:owner) { find_or_create_platform_owner }
  let(:customer) { owner.customer }
  let(:other_customer) { create(:customer) }
  let!(:student) { create(:entity, :with_name_status_schema, customer: customer, name: "Student", display_label: "Student") }
  let!(:order) { create(:entity, customer: customer, name: "Order", display_label: "Order") }
  let!(:foreign) { create(:entity, customer: other_customer, name: "Foreign") }
  let(:domain) { create(:entity_domain, customer: customer, name: "Academics") }

  let(:index_path) { admin_maintenance_entities_path(customer.id) }
  let(:domains_path) { admin_maintenance_entity_domains_path(customer.id) }
  let(:domain_path) { admin_maintenance_entity_domain_path(customer.id, domain) }
  let(:move_path) { admin_maintenance_entity_domain_membership_path(customer.id, student) }
  let(:domain_params) { { entity_domain: { name: "Forged", color: "blue", entity_ids: [student.id] } } }

  def owner_only_requests
    [
      [:get, new_admin_maintenance_entity_domain_path(customer.id)],
      [:post, domains_path],
      [:get, edit_admin_maintenance_entity_domain_path(customer.id, domain)],
      [:patch, domain_path],
      [:delete, domain_path],
      [:get, edit_admin_maintenance_entity_domain_membership_path(customer.id, student)],
      [:patch, move_path]
    ]
  end

  def expect_no_writes
    expect(EntityDomain.pluck(:name)).to eq(["Academics"])
    expect(EntityDomainMembership.count).to eq(0)
  end

  it "redirects anonymous users to sign in" do
    owner_only_requests.each do |verb, path|
      public_send(verb, path, params: domain_params.merge(entity_domain_membership: { entity_domain_id: domain.id }))
      expect(response).to redirect_to(new_user_session_path)
    end
    expect_no_writes
  end

  it "forbids a same-tenant admin and a member on every action" do
    [create(:user, :admin, customer: customer), create(:user, :member, customer: customer)].each do |user|
      sign_in user
      owner_only_requests.each do |verb, path|
        public_send(verb, path, params: domain_params.merge(entity_domain_membership: { entity_domain_id: domain.id }),
                                headers: { "Accept" => "application/json" })
        expect(response).to have_http_status(:forbidden), "#{user.email} #{verb} #{path}"
      end
      sign_out user
    end
    expect_no_writes
  end

  it "forbids a tenant admin on their own customer's domain routes" do
    admin = create(:user, :admin, customer: other_customer)
    sign_in admin
    get new_admin_maintenance_entity_domain_path(other_customer.id), headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:forbidden)
  end

  context "as the platform owner" do
    before { sign_in owner }

    def domain_index_path(record) = admin_maintenance_entities_path(customer.id, domain_id: record.id)

    it "creates a domain from its details and lands on it" do
      post domains_path, params: { entity_domain: { name: "Academics 2", color: "green", description: "Courses",
                                                    entity_ids: [student.id.to_s] } }

      created = EntityDomain.find_by!(name: "Academics 2")
      expect(response).to redirect_to(domain_index_path(created))
      expect(created).to have_attributes(description: "Courses", color: "green")
      expect(EntityDomainMembership.count).to eq(0)

      follow_redirect!
      header = Nokogiri::HTML(response.body).at_css("[data-role='domain-header']")
      expect(header.text).to include("Academics 2", "Courses")
    end

    it "re-renders the form with the attempted values on a validation error" do
      domain
      post domains_path, params: { entity_domain: { name: "academics", color: "blue" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML(response.body).at_css("#entity-domain-name")["value"]).to eq("academics")
      expect(response.body).to include(I18n.t("maint_core.entity_domains.errors.name_taken"))
    end

    it "edits and renames a domain" do
      get edit_admin_maintenance_entity_domain_path(customer.id, domain)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("maint_core.entity_domains.delete_dialog.confirm"))

      patch domain_path, params: { entity_domain: { name: "Academics (renamed)", color: "teal" } }
      expect(response).to redirect_to(domain_index_path(domain))
      expect(domain.reload).to have_attributes(name: "Academics (renamed)", color: "teal")
    end

    it "deletes a domain with the entities and journeys it holds" do
      EntityDomains::Memberships.place!(student, domain)
      journey = create(:journey, customer: customer, entity_domain: domain)

      delete domain_path

      expect(response).to redirect_to(index_path)
      expect(flash[:notice]).to eq(I18n.t("maint_core.entity_domains.flash.deleted", name: "Academics"))
      expect(EntityDomain.exists?(domain.id)).to be(false)
      expect(Entity.with_deleted.exists?(student.id)).to be(false)
      expect(Journey.exists?(journey.id)).to be(false)
      expect(Entity.exists?(order.id)).to be(true)
    end

    it "keeps a domain that another domain's entity links into and says why" do
      order.update!(associations: [{ "target_entity_id" => student.id, "target_entity_name" => "Student",
                                     "display_field" => "name", "display_field_label" => "Name" }].to_json)
      EntityDomains::Memberships.place!(student, domain)
      EntityDomains::Memberships.place!(order, create(:entity_domain, customer: customer, name: "Commerce"))

      delete domain_path

      expect(response).to redirect_to(domain_index_path(domain))
      expect(flash[:alert]).to eq(I18n.t("maint_core.entity_domains.errors.linked_from_outside", names: "Order"))
      expect(EntityDomain.exists?(domain.id)).to be(true)
      expect(Entity.exists?(student.id)).to be(true)
    end

    it "returns 404 for another customer's domain or entity on this URL" do
      foreign_domain = create(:entity_domain, customer: other_customer)

      get edit_admin_maintenance_entity_domain_path(customer.id, foreign_domain)
      expect(response).to have_http_status(:not_found)
      # A raised 404 never writes the session cookie, so sign in again.
      sign_in owner
      get edit_admin_maintenance_entity_domain_membership_path(customer.id, foreign)
      expect(response).to have_http_status(:not_found)
    end

    it "moves an entity into another domain but never out of every domain" do
      get edit_admin_maintenance_entity_domain_membership_path(customer.id, student)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("select[name='entity_domain_membership[entity_domain_id]']")["required"]).to be_present

      patch move_path, params: { entity_domain_membership: { entity_domain_id: domain.id } }
      expect(response).to redirect_to(domain_index_path(domain))
      expect(EntityDomainMembership.find_by(entity: student).entity_domain).to eq(domain)

      patch move_path, params: { entity_domain_membership: { entity_domain_id: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(EntityDomainMembership.find_by(entity: student).entity_domain).to eq(domain)
    end

    it "refuses a move into another customer's domain" do
      foreign_domain = create(:entity_domain, customer: other_customer)
      patch move_path, params: { entity_domain_membership: { entity_domain_id: foreign_domain.id } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(EntityDomainMembership.count).to eq(0)
    end

    it "places another tenant's entities on that tenant's URL" do
      tenant_domain = create(:entity_domain, customer: other_customer, name: "Tenant domain")
      patch admin_maintenance_entity_domain_membership_path(other_customer.id, foreign),
            params: { entity_domain_membership: { entity_domain_id: tenant_domain.id } }

      expect(response).to redirect_to(admin_maintenance_entities_path(other_customer.id, domain_id: tenant_domain.id))
      expect(EntityDomainMembership.find_by(entity: foreign).customer_id).to eq(other_customer.id)
    end

    it "shows one domain at a time with its entities and its journeys" do
      commerce = create(:entity_domain, customer: customer, name: "Commerce")
      EntityDomains::Memberships.place!(student, domain)
      EntityDomains::Memberships.place!(order, commerce)
      create(:journey, customer: customer, entity_domain: domain, name: "Enrolment")
      create(:journey, customer: customer, entity_domain: commerce, name: "Checkout")

      get index_path, params: { domain_id: domain.id }

      html = Nokogiri::HTML(response.body)
      expect(html.css("[data-entity-domain-key]").map { |node| node["data-entity-domain-key"] })
        .to eq([domain.id.to_s, commerce.id.to_s])
      expect(html.at_css("[data-role='domain-header']").text).to include("Academics")
      expect(html.css("[data-role='domain-entities'] [data-entity-id]").map { |node| node["data-entity-id"].to_i }).to eq([student.id])
      journeys = html.at_css("[data-role='domain-journeys']")
      expect(journeys.text).to include("Enrolment")
      expect(journeys.text).not_to include("Checkout")
      expect(journeys.at_css("a[href='#{new_admin_maintenance_journey_path(customer.id, domain_id: domain.id)}']")).to be_present
      expect(html.at_css("[data-role='domain-header'] a[href='#{new_admin_maintenance_entity_path(customer.id, domain_id: domain.id)}']"))
        .to be_present
    end

    it "filters the domain's entities by kind" do
      EntityDomains::Memberships.place!(student, domain)

      get index_path, params: { domain_id: domain.id, kind: "bridge" }

      html = Nokogiri::HTML(response.body)
      expect(html.css("[data-entity-id]")).to be_empty
      expect(response.body).to include(I18n.t("maint_core.entity_domains.index.no_matches"))
    end

    it "asks for a first domain when the customer has none" do
      get index_path

      expect(Nokogiri::HTML(response.body).at_css("[data-role='no-domains']").text)
        .to include(I18n.t("maint_core.entity_domains.workspace.no_domains_title"))
    end

    it "offers the flat table with view=table and a move action per row" do
      get index_path, params: { view: "table" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-entity-domains")
      expect(response.body).to include(edit_admin_maintenance_entity_domain_membership_path(customer.id, student))
    end

    it "switches between the domain view and the table" do
      domain
      get index_path

      switch = Nokogiri::HTML(response.body).at_css("nav[aria-label='#{I18n.t('maint_core.entity_domains.views.label')}']")
      expect(switch.css("a").map { |link| [link.text.strip, link["href"]] }).to eq([
        [I18n.t("maint_core.entity_domains.views.domains"), index_path],
        [I18n.t("maint_core.entity_domains.views.table"), "#{index_path}?view=table"]
      ])
      expect(switch.at_css("a[aria-current='page']")["href"]).to eq(index_path)
    end

    it "keeps the JSON reference catalog unaffected by the grouped view" do
      get index_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |item| item["id"] }).to include(student.id, order.id)
    end
  end

  it "shows tenant admins the flat table without any domain controls" do
    admin_customer = create(:customer)
    create(:entity, customer: admin_customer, name: "Lonely")
    sign_in create(:user, :admin, customer: admin_customer)

    get admin_maintenance_entities_path(admin_customer.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-entity-domains")
    expect(response.body).not_to include("/entity_domains")
    expect(response.body).not_to include("entity_domain_membership")
  end
end
