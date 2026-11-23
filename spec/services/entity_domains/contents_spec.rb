# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDomains::Contents do
  let(:customer) { create(:customer) }
  let(:domain) { create(:entity_domain, customer: customer) }
  let(:elsewhere) { create(:entity_domain, customer: customer) }
  let!(:student) { create(:entity, :with_name_status_schema, customer: customer, name: "Student") }

  subject(:contents) { described_class.new(domain) }

  before { EntityDomains::Memberships.place!(student, domain) }

  def reference_to(entity)
    [{ "name" => "Student", "name_slug" => "student", "html_type" => "select",
       "config" => { "options_source" => "entity_entries", "entity_id" => entity.id.to_s, "label_field" => "name" } }].to_json
  end

  it "counts trashed member entities and their records, but not shared members" do
    trashed = create(:entity, customer: customer, name: "Old")
    EntityDomains::Memberships.place!(trashed, domain)
    EntityDomains::Memberships.place!(create(:entity, :shared), domain)
    create(:entity_entry, customer: customer, entity: student)
    trashed.soft_delete

    expect(contents.entities.map(&:id)).to contain_exactly(student.id, trashed.id)
    expect(contents.record_count).to eq(1)
  end

  it "finds the customer's pages bound to member entities, trashed ones included" do
    live = create(:page, customer: customer, entity: student)
    trashed = create(:page, customer: customer, entity: student).tap(&:soft_delete)
    create(:page, customer: customer)
    create(:page, customer: create(:customer), entity: student)

    expect(contents.pages.map(&:id)).to contain_exactly(live.id, trashed.id)
  end

  it "names entities of other domains that reference a member through a field" do
    homework = create(:entity, customer: customer, name: "Homework", display_label: "Homework", property_schema: reference_to(student))
    EntityDomains::Memberships.place!(homework, elsewhere)

    expect(contents.outside_links).to eq([homework])
  end

  it "counts a trashed entity of another domain as a link, since it can be restored" do
    homework = create(:entity, customer: customer, name: "Homework", property_schema: reference_to(student))
    EntityDomains::Memberships.place!(homework, elsewhere)
    homework.soft_delete

    expect(contents.outside_links.map(&:id)).to eq([homework.id])
  end

  it "ignores links from inside the domain" do
    inside = create(:entity, customer: customer, name: "Grade", property_schema: reference_to(student))
    EntityDomains::Memberships.place!(inside, domain)

    expect(contents.outside_links).to be_empty
  end
end
