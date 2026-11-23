# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::EntityEntryPersonLinks", type: :request do
  include_context "as admin"

  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:property_schema) do
    [
      { "name" => "Name", "name_slug" => "name", "display_label" => "Name", "html_type" => "text", "type" => "String" }
    ]
  end

  let!(:entity) { create_person_entity(customer) }
  let!(:entry) { create(:entity_entry, :with_data, customer: customer, entity: entity, entry_data: { "name" => "Ada" }) }
  let(:link_path) { admin_entity_entry_person_link_path(customer.id, entity, entry) }
  let(:candidates_path) { candidates_admin_entity_entry_person_link_path(customer.id, entity, entry) }
  let(:entry_path) { admin_entity_entry_path(customer.id, entity, entry) }
  let(:member_user) { create(:user, :member, customer: customer, first_name: "Mina", last_name: "Member") }

  def create_person_entity(for_customer, **attrs)
    enable_module!("authentication", for_customer).set_extendable_model!(person_model, true)
    create(:entity, {
      customer: for_customer,
      name: "Person",
      extended_model: person_model,
      property_schema: property_schema.to_json
    }.merge(attrs))
  end

  describe "authorization" do
    let(:guard_path) { link_path }

    it_behaves_like "an admin-guarded request", :post

    context "on GET candidates" do
      let(:guard_path) { candidates_path }

      it_behaves_like "an admin-guarded GET"
    end
  end

  describe "POST create" do
    it "requires user_id" do
      post link_path
      expect(response).to have_http_status(:bad_request)
    end

    it "404s a non-person entity" do
      other = create(:entity, customer: customer, name: "Course", property_schema: property_schema.to_json)
      other_entry = create(:entity_entry, customer: customer, entity: other)

      post admin_entity_entry_person_link_path(customer.id, other, other_entry), params: { user_id: member_user.id }
      expect(response).to have_http_status(:not_found)
    end

    it "404s another tenant's entity" do
      foreign_customer = create(:customer)
      foreign_entity = create_person_entity(foreign_customer, name: "ForeignPerson")
      foreign_entry = create(:entity_entry, customer: foreign_customer, entity: foreign_entity)

      post admin_entity_entry_person_link_path(customer.id, foreign_entity, foreign_entry),
           params: { user_id: member_user.id }
      expect(response).to have_http_status(:not_found)
    end

    it "404s another tenant's entry on this entity" do
      foreign_entry = create(:entity_entry, customer: create(:customer), entity: create(:entity))

      post admin_entity_entry_person_link_path(customer.id, entity, foreign_entry),
           params: { user_id: member_user.id }
      expect(response).to have_http_status(:not_found)
    end

    it "refuses writes when the entity is inactive" do
      entity.update!(status: :inactive)

      post link_path, params: { user_id: member_user.id }
      expect(response).to have_http_status(:not_found)
    end

    it "links the entry and flashes the notice" do
      post link_path, params: { user_id: member_user.id }

      expect(response).to redirect_to(entry_path)
      expect(flash[:notice]).to eq(I18n.t("admin_misc.person_link.flash.linked"))
      expect(entry.reload).to be_linked
      expect(entry.user_id).to eq(member_user.id)
    end

    it "redirects with the service errors when linking fails" do
      People::Link.link!(entry: entry, user_id: member_user.id, actor: admin)

      post link_path, params: { user_id: member_user.id }

      expect(response).to redirect_to(entry_path)
      expect(flash[:alert]).to eq(I18n.t("people.errors.already_linked"))
    end

    it "uses the same generic error for a missing id and a cross-tenant user id" do
      foreign = create(:user, :member, customer: create(:customer))
      message = I18n.t("people.errors.user_unavailable")

      post link_path, params: { user_id: 999_999_999 }
      expect(response).to redirect_to(entry_path)
      expect(flash[:alert]).to eq(message)
      expect(entry.reload.user_id).to be_nil

      post link_path, params: { user_id: foreign.id }
      expect(response).to redirect_to(entry_path)
      expect(flash[:alert]).to eq(message)
      expect(entry.reload.user_id).to be_nil
    end

    it "links the same user to a second person entity" do
      other = create_person_entity(customer, name: "Volunteer")
      other_entry = create(:entity_entry, customer: customer, entity: other)

      post link_path, params: { user_id: member_user.id }
      post admin_entity_entry_person_link_path(customer.id, other, other_entry), params: { user_id: member_user.id }

      expect(entry.reload.user_id).to eq(member_user.id)
      expect(other_entry.reload.user_id).to eq(member_user.id)
    end
  end

  describe "DELETE" do
    it "offers no unlink: a linked entry stays linked" do
      People::Link.link!(entry: entry, user_id: member_user.id, actor: admin)

      delete link_path

      expect(response).to have_http_status(:not_found)
      expect(entry.reload.user_id).to eq(member_user.id)
    end
  end

  describe "GET candidates" do
    let!(:same_tenant_user) { create(:user, :member, customer: customer, first_name: "Same", last_name: "Tenant") }
    let!(:foreign_user) { create(:user, :member, customer: create(:customer), first_name: "Other", last_name: "Tenant") }

    it "404s a non-person entity" do
      other = create(:entity, customer: customer, name: "Course")
      other_entry = create(:entity_entry, customer: customer, entity: other)

      get candidates_admin_entity_entry_person_link_path(customer.id, other, other_entry), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "404s another tenant's entity" do
      foreign_customer = create(:customer)
      foreign_entity = create_person_entity(foreign_customer, name: "ForeignPerson")
      foreign_entry = create(:entity_entry, customer: foreign_customer, entity: foreign_entity)

      get candidates_admin_entity_entry_person_link_path(customer.id, foreign_entity, foreign_entry), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "404s another tenant's entry on this entity" do
      foreign_entry = create(:entity_entry, customer: create(:customer), entity: create(:entity))

      get candidates_admin_entity_entry_person_link_path(customer.id, entity, foreign_entry), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "rejects a non-JSON request" do
      get candidates_path
      expect(response).to have_http_status(:not_acceptable)
    end

    it "returns tenant users and never another tenant's users" do
      get candidates_path, params: { q: "Same" }, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.fetch("users").map { |row| row.fetch("id") }
      expect(ids).to include(same_tenant_user.id)
      expect(ids).not_to include(foreign_user.id)
      row = response.parsed_body.fetch("users").find { |item| item.fetch("id") == same_tenant_user.id }
      expect(row.fetch("name")).to eq(same_tenant_user.display_name)
      expect(row.fetch("email")).to eq(same_tenant_user.email)
    end

    it "never lists inactive users or users already linked to this entity" do
      available = member_user
      inactive = create(:user, :inactive, customer: customer, first_name: "Inez", last_name: "Idle")
      taken = create(:user, :member, customer: customer, first_name: "Taken", last_name: "Linked")
      create(:entity_entry, customer: customer, entity: entity, user: taken)

      get candidates_path, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.fetch("users").map { |row| row.fetch("id") }
      expect(ids).to include(same_tenant_user.id, available.id)
      expect(ids).not_to include(inactive.id, taken.id, foreign_user.id)
    end
  end

  describe "platform owner on another tenant's URL" do
    let(:owner) { find_or_create_platform_owner }

    before { sign_in owner }

    it "can list candidates and still only sees the URL tenant's users" do
      ours = create(:user, :member, customer: customer, first_name: "Url", last_name: "Tenant")
      theirs = create(:user, :member, customer: owner.customer, first_name: "Owner", last_name: "Home")

      get candidates_path, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.fetch("users").map { |row| row.fetch("id") }
      expect(ids).to include(ours.id)
      expect(ids).not_to include(theirs.id)
    end

    it "can link" do
      post link_path, params: { user_id: member_user.id }
      expect(response).to redirect_to(entry_path)
      expect(flash[:notice]).to eq(I18n.t("admin_misc.person_link.flash.linked"))
    end

    it "cannot link a user from another tenant" do
      foreign = create(:user, :member, customer: owner.customer)

      post link_path, params: { user_id: foreign.id }

      expect(response).to redirect_to(entry_path)
      expect(flash[:alert]).to eq(I18n.t("people.errors.user_unavailable"))
      expect(entry.reload.user_id).to be_nil
    end

    it "404s another tenant's entry even when the actor is the owner" do
      foreign_customer = create(:customer)
      foreign_entity = create_person_entity(foreign_customer, name: "OwnerForeign")
      foreign_entry = create(:entity_entry, customer: foreign_customer, entity: foreign_entity)

      post admin_entity_entry_person_link_path(customer.id, foreign_entity, foreign_entry),
           params: { user_id: member_user.id }
      expect(response).to have_http_status(:not_found)
      expect(foreign_entry.reload.user_id).to be_nil
    end
  end

  describe "admin of this tenant on another tenant's URL" do
    let(:foreign_customer) { create(:customer) }
    let(:foreign_entity) { create_person_entity(foreign_customer, name: "ForeignPerson") }
    let(:foreign_entry) { create(:entity_entry, customer: foreign_customer, entity: foreign_entity) }
    let(:foreign_user) { create(:user, :member, customer: foreign_customer) }

    it "is rejected for create and candidates" do
      post admin_entity_entry_person_link_path(foreign_customer.id, foreign_entity, foreign_entry),
           params: { user_id: foreign_user.id }
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(response.status).not_to eq(200)
      expect(foreign_entry.reload.user_id).to be_nil

      get candidates_admin_entity_entry_person_link_path(foreign_customer.id, foreign_entity, foreign_entry), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
