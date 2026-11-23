# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivitySteps::PopulatePrimary do
  describe ".call" do
    let(:model) { OpenStruct.new(data: {}) }

    before do
      # Allow hash-style access for entity attributes
      def model.[](key)
        data[key]
      end

      def model.[]=(key, value)
        data[key] = value
      end
    end

    it "rejects an actual base record even when fields are disguised as entity params" do
      user = create(:user, :member)
      original_email = user.email
      ctx = { model: user, routed_params: { primary: { base_models: {}, entity: { "email" => "forged@example.com" } } },
        authentication: { user_id: user.id }, current_user_id: user.id, current_user_role: "owner" }
      expect(described_class.call(ctx, **ctx)).to be(false)
      expect(user.email).to eq(original_email)
      expect(ctx[:error]).to eq(I18n.t("common.errors.dynamic.base_model_submission_not_supported"))
    end

    context "with entity params" do
      let(:ctx) do
        {
          model: model,
          routed_params: {
            primary: {
              base_models: {},
              entity: { "grade" => "A", "gpa" => "3.8" }
            }
          }
        }
      end

      it "assigns entity attributes via hash-style access" do
        described_class.call(ctx, **ctx)
        expect(model["grade"]).to eq("A")
        expect(model["gpa"]).to eq("3.8")
      end

      it "returns true" do
        result = described_class.call(ctx, **ctx)
        expect(result).to be true
      end

      it "never assigns internal columns such as user_id or customer_id" do
        ctx[:routed_params][:primary][:entity] = { "grade" => "A", "user_id" => 5, :customer_id => 9, "id" => 1 }
        described_class.call(ctx, **ctx)
        expect(model.data).to eq("grade" => "A")
      end
    end

    context "with base model params (non-EntityEntry)" do
      let(:model_with_assign) do
        obj = OpenStruct.new(data: {}, email: nil)
        def obj.assign_attributes(attrs)
          attrs.each { |k, v| send("#{k}=", v) }
        end

        def obj.[](key)
          data[key]
        end

        def obj.[]=(key, value)
          data[key] = value
        end
        obj
      end

      let(:ctx) do
        {
          model: model_with_assign,
          routed_params: {
            primary: {
              base_models: { "User" => { "email" => "test@example.com" } },
              entity: {}
            }
          }
        }
      end

      it "rejects base-model writes without calling assign_attributes" do
        expect(model_with_assign).not_to receive(:assign_attributes)
        expect(described_class.call(ctx, **ctx)).to be(false)
        expect(model_with_assign.email).to be_nil
        expect(ctx[:error]).to eq(I18n.t("common.errors.dynamic.base_model_submission_not_supported"))
      end
    end

    context "with base model params on EntityEntry" do
      let(:entity_entry_model) do
        obj = OpenStruct.new(data: {})
        def obj.is_a?(klass)
          klass == EntityEntry || super
        end

        def obj.[](key)
          data[key]
        end

        def obj.[]=(key, value)
          data[key] = value
        end
        obj
      end

      let(:ctx) do
        {
          model: entity_entry_model,
          routed_params: {
            primary: {
              base_models: { "User" => { "email" => "test@example.com" } },
              entity: { "grade" => "A" }
            }
          }
        }
      end

      it "does not merge base metadata into entity JSON or partially assign entity fields" do
        expect(described_class.call(ctx, **ctx)).to be(false)
        expect(entity_entry_model.data).to eq({})
        expect(ctx[:error]).to eq(I18n.t("common.errors.dynamic.base_model_submission_not_supported"))
      end
    end
  end
end
