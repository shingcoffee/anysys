# frozen_string_literal: true

module People
  module Activities
    # Creates a person-entity entry from the admin entry form and links it to
    # +user+ in one transaction, so a link that fails leaves no unlinked entry
    # behind. Entry validation is Entities::Activities::CreateEntry's; the link
    # rules are People::Activities::Link's. A user who already has an entry
    # of the entity ends on :already_linked.
    class CreateLinkedEntry < Trailblazer::Activity::Railway
      step :authorize, Output(:failure) => End(:forbidden)
      step :ensure_unlinked, Output(:failure) => End(:already_linked)
      step :create_entry
      step :link
      fail :collect_errors

      def self.call(customer:, actor:, user:, entity:, params:)
        result = nil
        EntityEntry.transaction(requires_new: true) do
          signal, (ctx, _) = super([{ customer: customer, actor: actor, user: user, entity: entity, params: params }, {}])
          result = [signal, ctx]
          raise ActiveRecord::Rollback unless signal.to_h[:semantic] == :success
        end
        result
      end

      def authorize(_ctx, customer:, actor:, user:, entity:, **)
        customer&.persisted? && actor&.admin_or_owner? &&
          (actor.customer_id == customer.id || actor.platform_owner?) &&
          user&.customer_id == customer.id && entity&.person?
      end

      def ensure_unlinked(_ctx, customer:, user:, entity:, **)
        !EntityEntry.exists?(customer_id: customer.id, entity_id: entity.id, user_id: user.id)
      end

      def create_entry(ctx, customer:, actor:, entity:, params:, **)
        signal, entry_ctx = Entities::Activities::CreateEntry.call(customer: customer, actor: actor, entity: entity, params: params)
        ctx[:form] = entry_ctx[:form]
        ctx[:model] = entry_ctx[:model]
        signal.to_h[:semantic] == :success
      end

      def link(ctx, model:, user:, actor:, **)
        result = People::Link.link!(entry: model, user_id: user.id, actor: actor)
        ctx[:link_errors] = result.errors
        result.success?
      end

      def collect_errors(ctx, customer:, entity:, params:, **)
        ctx[:form] ||= Entities::EntryForm.new(entity: entity, customer: customer, params: params)
        ctx[:form].add_errors!("base" => ctx[:link_errors]) if ctx[:link_errors].present?
        ctx[:errors] = ctx[:form].errors
        true
      end
    end
  end
end
