# frozen_string_literal: true

module Entities
  module Activities
    # Rewrites one bridge row of a primary entry. The reference back to the
    # entry stays fixed; the target and the bridge's own attributes are editable.
    class UpdateAssociationEntry < Trailblazer::Activity::Railway
      include AssociationEntryWriter

      step :authorize, Output(:failure) => End(:forbidden)
      step :find_row, Output(:failure) => End(:forbidden)
      step :build_form
      step :validate
      step :persist
      fail :collect_errors

      def self.call(customer:, actor:, entity:, entry:, association_id:, row:, params:)
        Current.set(customer: customer, shared_resources_mode: false) do
          signal, (ctx, _) = super([{ customer: customer, actor: actor, entity: entity, entry: entry,
                                      association_id: association_id, row: row, params: params, errors: {} }, {}])
          [signal, ctx]
        end
      end

      def find_row(ctx, customer:, association:, entry:, row:, **)
        ctx[:row] = EntryAssociations.new(entity: ctx[:entity], customer: customer)
                                     .rows(association, entry).find_by(id: row&.id)
        ctx[:row].present?
      end

      def build_form(ctx, row:, params:, **)
        form = ctx[:form] = association_form(ctx, params: params, row: row)
        reject_nil_params(form, params)
        ctx[:model] = EntityEntry.build_for(form.entity).find(row.id).tap { |model| model.entity = form.entity }
        form.available? && form.errors.empty?
      end

      def persist(_ctx, contract:, form:, **)
        persist_entry(contract: contract, form: form)
      end

      private

      def save_failed_key = "update_failed"
    end
  end
end
