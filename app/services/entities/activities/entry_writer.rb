# frozen_string_literal: true

module Entities
  module Activities
    # Steps shared by the admin entry writers (CreateEntry and the association
    # entry writers). The including activity builds ctx[:form] and ctx[:model]
    # and names its fallback error through #save_failed_key.
    module EntryWriter
      def authorize(ctx, customer:, actor:, entity:, **)
        return false unless customer&.persisted? && actor&.admin_or_owner?
        return false unless actor.customer_id == customer.id || actor.platform_owner?

        ctx[:entity] = Entity.where(customer_id: customer.id).or(Entity.shared)
                             .active.non_bridge.find_by(id: entity&.id)
        ctx[:entity].present?
      end

      def validate(ctx, form:, model:, **)
        contract = ctx[:contract] = EntityEntryContract.build_for(
          form.entity, audience: "admin", writable_slugs: form.writable_slugs
        ).new(model)
        contract.validate(form.filtered_input)
      end

      def persist(_ctx, contract:, form:, **)
        persist_entry(contract: contract, form: form)
      end

      def collect_errors(ctx, form:, model:, **)
        form.add_errors!(ctx[:contract].errors.messages) if ctx[:contract]
        form.add_errors!(model.errors.messages) if model
        if form.errors.empty?
          form.add_errors!("base" => [I18n.t("admin_misc.entities.entry_form.errors.#{save_failed_key}")])
        end
        ctx[:errors] = form.errors
        true
      end

      private

      def persist_entry(contract:, form:)
        return false if form.errors.any?

        result = Entries::Save.call(contract: contract, audience: "admin")
        form.add_errors!("base" => result.errors) unless result.ok?
        result.ok?
      end

      def reject_nil_params(form, params)
        # nil is EntryForm's GET mode, never a submitted data object.
        return unless params.nil?

        form.add_errors!("base" => [I18n.t("admin_misc.entities.entry_form.errors.invalid_shape")])
      end
    end
  end
end
