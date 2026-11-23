# frozen_string_literal: true

module Entities
  module Activities
    # Adds one or more bridge rows linking a primary entry to records of an
    # associated entity (e.g. a student's course enrollments with their
    # grades). Every row is validated; rows save together or not at all.
    class CreateAssociationEntries < Trailblazer::Activity::Railway
      include AssociationEntryWriter

      MAX_ROWS = 50

      step :authorize, Output(:failure) => End(:forbidden)
      step :build_forms
      step :validate_rows
      step :persist_rows
      fail :collect_row_errors

      def self.call(customer:, actor:, entity:, entry:, association_id:, rows:)
        Current.set(customer: customer, shared_resources_mode: false) do
          signal, (ctx, _) = super([{ customer: customer, actor: actor, entity: entity, entry: entry,
                                      association_id: association_id, rows: rows, errors: {} }, {}])
          [signal, ctx]
        end
      end

      def build_forms(ctx, rows:, **)
        list = rows.is_a?(Array) ? rows : []
        ctx[:forms] = list.first(MAX_ROWS).map { |row| association_form(ctx, params: row) }
        if list.empty?
          ctx[:forms] = [association_form(ctx, params: nil)]
          ctx[:errors] = { "base" => [I18n.t("admin_misc.entities.association_entries.errors.no_rows")] }
        elsif list.size > MAX_ROWS
          ctx[:errors] = { "base" => [I18n.t("admin_misc.entities.association_entries.errors.too_many_rows", count: MAX_ROWS)] }
        end
        ctx[:errors].empty? && ctx[:forms].first.available?
      end

      # A row whose input already failed the form boundary skips the contract,
      # but the other rows are still checked so every error shows at once.
      def validate_rows(ctx, forms:, customer:, **)
        ctx[:checks] = forms.select { |form| form.errors.empty? }.map do |form|
          model = EntityEntry.build_for(form.entity).new(entity: form.entity, customer_id: customer.id)
          contract = EntityEntryContract.build_for(form.entity, audience: "admin", writable_slugs: form.writable_slugs).new(model)
          { form: form, model: model, contract: contract, valid: contract.validate(form.filtered_input) }
        end
        ctx[:checks].size == forms.size && ctx[:checks].all? { |check| check[:valid] }
      end

      def persist_rows(ctx, checks:, **)
        saved = false
        EntityEntry.transaction(requires_new: true) do
          saved = checks.all? do |check|
            result = Entries::Save.call(contract: check[:contract], audience: "admin")
            check[:form].add_errors!("base" => result.errors) unless result.ok?
            result.ok?
          end
          raise ActiveRecord::Rollback unless saved
        end
        ctx[:models] = checks.map { |check| check[:model] } if saved
        saved
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
        false
      end

      def collect_row_errors(ctx, **)
        Array(ctx[:checks]).each do |check|
          check[:form].add_errors!(check[:contract].errors.messages)
          check[:form].add_errors!(check[:model].errors.messages)
        end
        if ctx[:errors].empty? && Array(ctx[:forms]).all? { |form| form.errors.empty? }
          ctx[:errors] = { "base" => [I18n.t("admin_misc.entities.entry_form.errors.save_failed")] }
        end
        true
      end
    end
  end
end
