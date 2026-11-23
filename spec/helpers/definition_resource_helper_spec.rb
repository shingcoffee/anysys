# frozen_string_literal: true

require "rails_helper"

RSpec.describe DefinitionResourceHelper do
  let(:helper) do
    Class.new do
      include DefinitionResourceHelper

      def current_customer_id = 81_721_200
      def t(key, **) = I18n.t(key, **)
      def admin_maintenance_path(*) = "/81721200/admin/maintenance"
      def admin_maintenance_entities_path(*) = "/81721200/admin/maintenance/entities"
    end.new
  end

  describe "#definition_resource_breadcrumbs" do
    it "builds Maintenance → resource on the index (last crumb has no path)" do
      crumbs = helper.definition_resource_breadcrumbs(:entities)
      expect(crumbs.map { |c| c[:label] }).to eq([ "Maintenance", "Entities" ])
      expect(crumbs.first[:path]).to eq("/81721200/admin/maintenance")
      expect(crumbs.last[:path]).to be_nil
    end

    it "links the resource crumb when a trail follows it" do
      crumbs = helper.definition_resource_breadcrumbs(:entities, "New")
      expect(crumbs[1][:path]).to eq("/81721200/admin/maintenance/entities")
      expect(crumbs.last).to eq(label: "New")
    end
  end

  describe "#definition_override_reset_action" do
    let(:helper) do
      Class.new do
        include DefinitionResourceHelper

        def current_customer_id = 81_721_200
        def t(key, **) = I18n.t(key, **)
        def shared_resources_mode? = false
        def admin_maintenance_entity_override_path(*) = "/81721200/admin/maintenance/entities/1/override"
      end.new
    end

    def record(shared:, overridden:)
      rec = instance_double(
        Entity,
        shared?: shared,
        model_name: instance_double(ActiveModel::Name, singular: "entity")
      )
      allow(rec).to receive(:customer_override?).and_return(overridden)
      rec
    end

    it "returns a delete action when the tenant has an override" do
      action = helper.definition_override_reset_action(record(shared: true, overridden: true))
      expect(action[:label]).to eq(I18n.t("maint_core.entities.show.reset_to_default"))
      expect(action[:path]).to eq("/81721200/admin/maintenance/entities/1/override")
      expect(action[:data][:turbo_method]).to eq(:delete)
    end

    it "returns nil when the resource is customer-owned" do
      expect(helper.definition_override_reset_action(record(shared: false, overridden: false))).to be_nil
    end

    it "returns nil when there is no override" do
      expect(helper.definition_override_reset_action(record(shared: true, overridden: false))).to be_nil
    end
  end
end
