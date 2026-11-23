# frozen_string_literal: true

require "rails_helper"

RSpec.describe "EntityDomains activities" do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let!(:student) { create(:entity, customer: customer, name: "Student") }
  let!(:course) { create(:entity, :with_name_status_schema, customer: customer, name: "Course") }
  let!(:shared) { create(:entity, :shared, name: "Country") }
  let!(:foreign) { create(:entity, customer: other_customer, name: "Foreign") }

  def members(domain) = EntityDomainMembership.where(entity_domain: domain).pluck(:entity_id)

  describe EntityDomains::Activities::Save do
    def save(domain, **params)
      described_class.call(domain: domain, params: params.stringify_keys, customer_id: customer.id)
    end

    it "creates a domain from its name, description and color" do
      domain = EntityDomain.new
      result = save(domain, name: " Academics ", description: "Courses", color: "green")

      expect(result).to be_success
      expect(domain.reload).to have_attributes(name: "Academics", description: "Courses", color: "green",
                                               customer_id: customer.id)
    end

    it "defaults a blank color to the first palette color" do
      domain = EntityDomain.new
      expect(save(domain, name: "Plain", color: "")).to be_success
      expect(domain.reload.color).to eq(EntityDomain::COLORS.first)
    end

    it "keeps members when the domain is renamed" do
      domain = create(:entity_domain, customer: customer)
      EntityDomainMembership.create!(customer: customer, entity_domain: domain, entity: course)

      expect(save(domain, name: "Renamed", entity_ids: [student.id.to_s])).to be_success
      expect(members(domain)).to eq([course.id])
    end

    it "validates name presence, case-insensitive uniqueness per customer, and color" do
      create(:entity_domain, customer: customer, name: "Academics")
      create(:entity_domain, customer: other_customer, name: "Commerce")

      blank = save(EntityDomain.new, name: " ", color: "blue")
      expect(blank.errors[:name]).to be_present

      taken = save(EntityDomain.new, name: "ACADEMICS", color: "blue")
      expect(taken.errors[:name]).to eq([I18n.t("maint_core.entity_domains.errors.name_taken")])

      expect(save(EntityDomain.new, name: "Commerce", color: "blue")).to be_success
      expect(save(EntityDomain.new, name: "Other", color: "neon").errors[:color]).to be_present
    end

    it "refuses a domain that belongs to another customer" do
      domain = create(:entity_domain, customer: other_customer, name: "Theirs")
      result = save(domain, name: "Hijacked")

      expect(result).not_to be_success
      expect(domain.reload.name).to eq("Theirs")
    end
  end

  describe EntityDomains::Activities::Assign do
    let(:domain) { create(:entity_domain, customer: customer) }
    let(:other_domain) { create(:entity_domain, customer: customer) }

    it "moves an entity from one domain into another" do
      expect(described_class.call(entity: student, domain_id: domain.id.to_s, customer_id: customer.id)).to be_success
      expect(members(domain)).to eq([student.id])

      expect(described_class.call(entity: student, domain_id: other_domain.id, customer_id: customer.id)).to be_success
      expect(members(domain)).to be_empty
      expect(members(other_domain)).to eq([student.id])
    end

    it "requires a domain, since an entity always belongs to one" do
      result = described_class.call(entity: student, domain_id: "", customer_id: customer.id)

      expect(result).not_to be_success
      expect(result.errors[:base]).to eq([I18n.t("maint_core.entity_domains.errors.domain_unavailable")])
      expect(EntityDomainMembership.count).to eq(0)
    end

    it "carries the bridges the entity declares along" do
      student.update!(associations: [{ "target_entity_id" => course.id, "target_entity_name" => "Course",
                                       "display_field" => "name", "display_field_label" => "Name" }].to_json)
      student.sync_bridge_entities!
      bridge_id = student.reload.associations_list.first["bridge_entity_id"]

      described_class.call(entity: student, domain_id: domain.id, customer_id: customer.id)

      expect(members(domain)).to contain_exactly(student.id, bridge_id)
      expect(members(domain)).not_to include(course.id)
    end

    it "refuses another customer's domain or entity" do
      foreign_domain = create(:entity_domain, customer: other_customer)

      expect(described_class.call(entity: student, domain_id: foreign_domain.id, customer_id: customer.id)).not_to be_success
      expect(described_class.call(entity: foreign, domain_id: domain.id, customer_id: customer.id)).not_to be_success
      expect(EntityDomainMembership.count).to eq(0)
    end
  end

  describe EntityDomains::Activities::Destroy do
    let(:domain) { create(:entity_domain, customer: customer) }

    def destroy = described_class.call(domain: domain, customer_id: customer.id)

    it "deletes the domain with its entities, their records and pages, and its journeys" do
      EntityDomains::Memberships.place!(student, domain)
      EntityDomains::Memberships.place!(shared, domain)
      create(:entity_entry, customer: customer, entity: student)
      page = create(:page, customer: customer, entity: student)
      journey = create(:journey, customer: customer, entity_domain: domain)
      kept_page = create(:page, customer: customer, entity: course)

      expect(destroy).to be_success
      expect(EntityDomain.exists?(domain.id)).to be(false)
      expect(Entity.with_deleted.exists?(student.id)).to be(false)
      expect(EntityEntry.where(entity_id: student.id)).to be_empty
      expect(Page.with_deleted.exists?(page.id)).to be(false)
      expect(Journey.exists?(journey.id)).to be(false)
      expect(EntityDomainMembership.count).to eq(0)
      expect(Entity.exists?(shared.id)).to be(true)
      expect(Entity.exists?(course.id)).to be(true)
      expect(Page.exists?(kept_page.id)).to be(true)
    end

    it "deletes the bridges the domain's entities declare" do
      student.update!(associations: [{ "target_entity_id" => course.id, "target_entity_name" => "Course",
                                       "display_field" => "name", "display_field_label" => "Name" }].to_json)
      student.sync_bridge_entities!
      bridge_id = student.reload.associations_list.first["bridge_entity_id"]
      EntityDomains::Memberships.place!(student, domain)
      EntityDomains::Memberships.place!(course, create(:entity_domain, customer: customer))

      expect(destroy).to be_success
      expect(Entity.with_deleted.where(id: [student.id, bridge_id])).to be_empty
      expect(Entity.exists?(course.id)).to be(true)
    end

    it "refuses while an entity of another domain still links in, and deletes nothing" do
      student.update!(associations: [{ "target_entity_id" => course.id, "target_entity_name" => "Course",
                                       "display_field" => "name", "display_field_label" => "Name" }].to_json)
      student.sync_bridge_entities!
      EntityDomains::Memberships.place!(course, domain)
      EntityDomains::Memberships.place!(student, create(:entity_domain, customer: customer))

      result = destroy

      expect(result).not_to be_success
      expect(result.errors[:base]).to eq([I18n.t("maint_core.entity_domains.errors.linked_from_outside",
                                                 names: student.display_label)])
      expect(EntityDomain.exists?(domain.id)).to be(true)
      expect(Entity.exists?(course.id)).to be(true)
    end

    it "reports a failed delete and rolls it back" do
      EntityDomains::Memberships.place!(student, domain)
      allow_any_instance_of(Entity).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, "locked")

      result = destroy

      expect(result).not_to be_success
      expect(result.errors[:base].first).to include("locked")
      expect(EntityDomain.exists?(domain.id)).to be(true)
    end

    it "refuses another customer's domain" do
      foreign_domain = create(:entity_domain, customer: other_customer)

      expect(described_class.call(domain: foreign_domain, customer_id: customer.id)).not_to be_success
      expect(EntityDomain.exists?(foreign_domain.id)).to be(true)
    end
  end

  it "drops memberships when the entity is destroyed" do
    domain = create(:entity_domain, customer: customer)
    EntityDomainMembership.create!(customer: customer, entity_domain: domain, entity: student)

    student.destroy!
    expect(EntityDomainMembership.count).to eq(0)
  end

  it "keeps en and zh-CN domain keys in parity" do
    flatten = lambda do |hash, prefix = nil|
      hash.flat_map { |key, value| value.is_a?(Hash) ? flatten.call(value, [prefix, key].compact.join(".")) : [[prefix, key].compact.join(".")] }
    end
    en = I18n.t("maint_core.entity_domains", locale: :en)
    zh = I18n.t("maint_core.entity_domains", locale: :"zh-CN")
    expect(flatten.call(zh)).to match_array(flatten.call(en))
  end
end
