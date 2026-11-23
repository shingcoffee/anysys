# frozen_string_literal: true

module Entities
  module Activities
    class CreateEntry < Trailblazer::Activity::Railway
      include EntryWriter

      step :authorize, Output(:failure) => End(:forbidden)
      step :build_form
      step :validate
      step :persist
      fail :collect_errors

      # The installed Activity API takes [input, flow_options]. Keep that detail
      # behind the agreed keyword boundary and retain tenant context through save.
      def self.call(customer:, actor:, entity:, params:)
        Current.set(customer: customer, shared_resources_mode: false) do
          signal, (ctx, _) = super([{ customer: customer, actor: actor, entity: entity, params: params, errors: {} }, {}])
          [signal, ctx]
        end
      end

      def build_form(ctx, entity:, customer:, params:, **)
        form = ctx[:form] = EntryForm.new(entity: entity, customer: customer, params: params)
        reject_nil_params(form, params)
        ctx[:entity] = form.entity
        ctx[:model] = EntityEntry.build_for(form.entity).new(entity: form.entity, customer_id: customer.id)
        form.available? && form.errors.empty?
      end

      private

      def save_failed_key = "save_failed"
    end
  end
end
