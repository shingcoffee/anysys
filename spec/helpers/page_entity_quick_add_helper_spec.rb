# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageEntityQuickAddHelper, type: :helper do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let!(:entity) { create(:entity, customer: customer, name: "Student", display_label: "") }

  def enable!(depth: 0, user: admin)
    customer_id = customer.id
    helper.define_singleton_method(:page_quick_add_depth) { depth }
    helper.define_singleton_method(:current_user) { user }
    helper.define_singleton_method(:current_customer_id) { customer_id }
  end

  it "is nil on surfaces that never enable quick add" do
    expect(helper.page_entity_quick_add(entity.id, "code")).to be_nil
  end

  it "is nil when the rendering controller leaves quick add off" do
    enable!(depth: nil)
    expect(helper.page_entity_quick_add(entity.id, "code")).to be_nil
  end

  it "is nil for a member even when enabled" do
    enable!(user: create(:user, :member, customer: customer))
    expect(helper.page_entity_quick_add(entity.id, "code")).to be_nil
  end

  it "is nil for a bridge entity" do
    enable!
    entity.update_columns(category: Entity.categories.fetch("bridge"))
    expect(helper.page_entity_quick_add(entity.id, "code")).to be_nil
  end

  it "is nil for a missing entity" do
    enable!
    expect(helper.page_entity_quick_add(0, "code")).to be_nil
  end

  it "builds the option for an admin, falling back to the entity name and dropping a blank label field" do
    enable!
    expect(helper.page_entity_quick_add(entity.id, "")).to eq(
      url:   "/#{customer.id}/admin/entities/#{entity.id}/entries/new",
      label: I18n.t("admin_misc.entities.quick_add.option"),
      title: I18n.t("admin_misc.entities.quick_add.title", name: "Student"),
      dialog: "#entity-quick-add-dialog-0"
    )
  end

  it "opens the dialog level the rendering controller names, and none past the deepest" do
    enable!(depth: 3)
    expect(helper.page_entity_quick_add(entity.id, "code")[:dialog]).to eq("#entity-quick-add-dialog-3")

    enable!(depth: Admin::Entities::QuickAddDialogComponent::MAX_DEPTH + 1)
    expect(helper.page_entity_quick_add(entity.id, "code")).to be_nil
  end

  it "looks each entity up once per render" do
    enable!
    helper.page_entity_quick_add(entity.id, "code")
    expect(Entity).not_to receive(:where)
    helper.page_entity_quick_add(entity.id, "other")
  end
end
