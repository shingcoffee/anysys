# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::EntryPageResolver do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer, name: "Student") }

  def config_with(extra)
    {
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "pages" => [{ "id" => "page_1", "fields" => [] }]
    }.merge(extra).to_json
  end

  def entry_page(modes: nil, page_customer: customer, **attributes)
    extra = modes ? { "form_settings" => { "modes" => modes } } : {}
    Current.set(customer: page_customer) do
      create(:page, customer: page_customer, entity: entity, launched: true, **attributes,
                    configuration: config_with(extra))
    end
  end

  def page_for(action, audience: EntityAttributeAudience::ADMIN)
    Current.set(customer: customer) { described_class.page_for(entity: entity, audience: audience, action: action) }
  end

  it "returns the newest launched page that serves the action" do
    create_only = entry_page(modes: ["create"])
    both = entry_page

    expect(page_for(:create)).to eq(both)
    expect(page_for(:update)).to eq(both)

    both.take_offline!
    expect(page_for(:update)).to be_nil
    expect(page_for(:create)).to eq(create_only)
  end

  it "resolves an update-only page for updates and not for creates" do
    update_only = entry_page(modes: ["update"])

    expect(page_for(:update)).to eq(update_only)
    expect(page_for(:create)).to be_nil
  end

  it "skips pages hidden from the audience" do
    entry_page(audience_admin: false, audience_member: true)

    expect(page_for(:create)).to be_nil
    expect(page_for(:update)).to be_nil
  end

  context "with a shared entity" do
    let(:entity) { create(:entity, :shared, name: "Student") }

    it "prefers the tenant's own page over a shared one" do
      shared = Current.set(customer: nil) do
        create(:page, :shared, entity: entity, launched: true, configuration: config_with({}))
      end
      expect(page_for(:create)).to eq(shared)

      own = entry_page
      expect(page_for(:create)).to eq(own)
    end
  end

  it "rejects an unknown action" do
    expect { page_for(:destroy) }.to raise_error(ArgumentError)
  end
end
