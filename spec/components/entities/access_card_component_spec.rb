# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::AccessCardComponent, type: :component do
  subject(:component) { described_class.new(entity: entity, customer_id: customer.id) }

  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, name: "Student")
  end

  def render_component
    with_request_url("/#{customer.id}/admin/maintenance/entities/#{entity.id}", host: "www.example.com") do
      render_inline(component)
    end
  end

  before { render_component }

  it "renders the Entries heading" do
    expect(page).to have_text("Entries")
  end

  it "renders the entries count badge" do
    expect(page).to have_text("0 entries")
  end

  it "links to the entity's entries page" do
    expect(page).to have_link("Open entries", href: "/#{customer.id}/admin/entities/#{entity.id}")
  end

  it "shows the access hint" do
    expect(page).to have_text("Browse and manage records")
  end

  it "does not render the name slug" do
    expect(page).not_to have_text("Name Slug")
    expect(page).not_to have_css("[data-controller='click-to-copy']")
  end

  it "counts only this customer's entries on a shared entity" do
    shared = create(:entity, :shared, name: "SharedPeople")
    create(:entity_entry, customer: customer, entity: shared)
    other = create(:customer)
    create(:entity_entry, customer: other, entity: shared)

    with_request_url("/#{customer.id}/admin/maintenance/entities/#{shared.id}", host: "www.example.com") do
      render_inline(described_class.new(entity: shared, customer_id: customer.id))
    end

    expect(page).to have_text("1 entry")
    expect(page).not_to have_text("2 entries")
  end
end
