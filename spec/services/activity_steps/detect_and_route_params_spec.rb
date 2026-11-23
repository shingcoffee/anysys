# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivitySteps::DetectAndRouteParams do
  describe ".call" do
    context "with flat single-source params" do
      it "wraps flat params as entity-only routed_params" do
        ctx = { params: { "name" => "John", "email" => "john@example.com" } }

        described_class.call(ctx)

        expect(ctx[:routed_params]).to eq({
          primary: { base_models: {}, entity: { "name" => "John", "email" => "john@example.com" } },
          associations: []
        })
      end

      it "returns true" do
        ctx = { params: { "name" => "John" } }
        expect(described_class.call(ctx)).to be true
      end
    end

    context "with empty params" do
      it "wraps empty params as empty entity" do
        ctx = { params: {} }

        described_class.call(ctx)

        expect(ctx[:routed_params]).to eq({
          primary: { base_models: {}, entity: {} },
          associations: []
        })
      end
    end

    context "with multi-source params including associations" do
      let_it_be(:customer) { create(:customer) }
      let(:primary_entity) do
        entity = create(:entity, name: "invoice", customer: customer)
        # update_columns skips validations: the routing logic only inspects the
        # blob shape and does not look up target_entity_id in the DB.
        entity.associations_json = [
            { "target_entity_id" => 100, "target_entity_name" => "course",
              "bridge_entity_id" => 200, "bridge_entity_name" => "assoc_invoice_course" }
          ]

        entity.save(validate: false)
        entity.reload
      end

      it "routes association params keyed by bridge entity name into bridge.params" do
        ctx = {
          params: {
            "entity" => { "invoice_id" => "S001" },
            "assoc"  => {
              "assoc_invoice_course" => { "course" => "12", "score" => "95" }
            }
          },
          bound_entity: primary_entity
        }

        described_class.call(ctx)

        expect(ctx[:routed_params][:primary]).to eq({
          base_models: {},
          entity: { "invoice_id" => "S001" }
        })

        assoc = ctx[:routed_params][:associations].first
        expect(assoc[:entity_id]).to eq(100)
        expect(assoc[:entity_name]).to eq("course")
        expect(assoc[:bridge][:entity_id]).to eq(200)
        expect(assoc[:bridge][:entity_name]).to eq("assoc_invoice_course")
        expect(assoc[:bridge][:params]).to eq({ "course" => "12", "score" => "95" })
      end

      it "routes association params keyed by bridge_entity_id into bridge.params" do
        ctx = {
          params: {
            "entity" => { "invoice_id" => "S001" },
            "assoc"  => {
              "200" => { "course" => "12", "score" => "95" }
            }
          },
          bound_entity: primary_entity
        }

        described_class.call(ctx)

        assoc = ctx[:routed_params][:associations].first
        expect(assoc[:entity_id]).to eq(100)
        expect(assoc[:bridge][:entity_id]).to eq(200)
        expect(assoc[:bridge][:params]).to eq({ "course" => "12", "score" => "95" })
      end

      it "skips assoc sections with no matching bridge entity" do
        ctx = {
          params: {
            "assoc" => { "unknown_bridge" => { "field" => "value" } }
          },
          bound_entity: primary_entity
        }

        described_class.call(ctx)

        expect(ctx[:routed_params][:associations]).to eq([])
      end
    end

    context "with only entity key (detected as multi-source)" do
      it "detects as multi-source when only entity key present" do
        ctx = {
          params: { "entity" => { "name" => "Test" } }
        }

        described_class.call(ctx)

        expect(ctx[:routed_params][:primary]).to eq({
          base_models: {},
          entity: { "name" => "Test" }
        })
      end
    end

    context "with no bound_entity for associations" do
      it "returns empty associations when bound_entity is nil" do
        ctx = {
          params: {
            "assoc" => { "assoc_student_course" => { "course" => "12" } }
          },
          bound_entity: nil
        }

        described_class.call(ctx)

        expect(ctx[:routed_params][:associations]).to eq([])
      end
    end

    context "with nil params" do
      it "handles nil params gracefully" do
        ctx = { params: nil }

        described_class.call(ctx)

        expect(ctx[:routed_params]).to eq({
          primary: { base_models: {}, entity: {} },
          associations: []
        })
      end
    end

    it "rejects base sections instead of manufacturing a routed write target from a class name" do
      ctx = { params: { "base" => { "Authentication::User" => { "id" => "7", "email" => "forged@example.com" } } },
        current_user_id: 7, current_user_role: "owner", authentication: { user_id: 7 } }
      expect(described_class.call(ctx)).to be(false)
      expect(ctx[:routed_params]).to be_nil
      expect(ctx[:error]).to eq(I18n.t("common.errors.dynamic.base_model_submission_not_supported"))
    end
  end

  describe ".multi_source?" do
    it "returns true when params have 'base' key" do
      expect(described_class.multi_source?({ "base" => {} })).to be true
    end

    it "returns true when params have 'entity' key" do
      expect(described_class.multi_source?({ "entity" => {} })).to be true
    end

    it "returns true when params have 'assoc' key" do
      expect(described_class.multi_source?({ "assoc" => {} })).to be true
    end

    it "returns false for flat params" do
      expect(described_class.multi_source?({ "name" => "John" })).to be false
    end

    it "returns false for nil" do
      expect(described_class.multi_source?(nil)).to be false
    end
  end
end
