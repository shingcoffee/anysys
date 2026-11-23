# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped find-or-initialize import. Never uses InsertAll. Writes go
  # through Entries.save (lifecycle and audience), never record.save!.
  module BulkImport
    class Error < StandardError; end

    MAX_ROWS = 1000
    DEFAULT_BATCH_SIZE = 500

    module_function

    def run(ctx, rows:, on_duplicate:, unique_by:, field_mappings: {}, batch_size: DEFAULT_BATCH_SIZE,
            on_row_error: "skip", entity: nil, record_scope: "all")
      list = Array(rows)
      return Step.fail(ctx, :"bulk_import.too_many_rows", count: list.size, max: MAX_ROWS) if list.size > MAX_ROWS

      keys = Array(unique_by).map(&:to_s).reject(&:empty?) - Entries::INTERNAL_COLUMNS
      mappings = field_mappings.respond_to?(:to_h) ? field_mappings.to_h : {}
      created = 0
      updated = 0
      skipped = 0
      failed = 0
      errors = []
      abort_index = nil
      scope = begin
        Entries.scoped(ctx, entity: entity, record_scope: record_scope)
      rescue Entries::Error
        return Step.fail(ctx, :"bulk_import.entity_not_accessible")
      end
      target = import_entity(ctx, entity, scope)
      return Step.fail(ctx, :"bulk_import.entity_not_accessible") unless target

      size = [[batch_size.to_i, 1].max, MAX_ROWS].min
      # Failing the import must roll back every row, so it commits as a single batch.
      size = [list.size, 1].max if on_row_error.to_s == "fail"

      list.each_slice(size).with_index do |batch, batch_index|
        ActiveRecord::Base.transaction do
          batch.each_with_index do |raw, inner|
            index = (batch_index * size) + inner
            ActiveRecord::Base.transaction(requires_new: true) do
              row = mapped_row(raw, mappings)
              outcome = write_row(ctx, scope, target, row, keys, on_duplicate)
              case outcome
              when :created then created += 1
              when :updated then updated += 1
              when :skipped then skipped += 1
              else
                raise StandardError, collect_row_error(ctx, outcome).presence || "invalid"
              end
            end
          rescue Error
            raise
          rescue => error
            if on_row_error.to_s == "fail"
              Step.fail(ctx, :"bulk_import.row_failed", index: index, reason: error.message)
              abort_index = index
              raise ActiveRecord::Rollback
            end
            failed += 1
            errors << { index: index, message: error.message }
          end
        end
        return false if abort_index
      end

      { created: created, updated: updated, skipped: skipped, failed: failed, errors: errors }
    end

    def import_entity(ctx, entity, scope)
      return entity if entity.is_a?(Entity)
      return ctx && ctx[:bound_entity] if entity.blank?

      klass = scope.klass
      klass.respond_to?(:bound_entity) ? klass.bound_entity : ctx && ctx[:bound_entity]
    end

    def write_row(ctx, scope, target, row, keys, on_duplicate)
      match = keys.to_h { |key| [key, row[key] || row[key.to_sym]] }
      record = keys.any? ? Entries.where(scope, match).first : nil
      if record
        return :skipped unless on_duplicate.to_s == "update"

        Entries.assign(record, row)
        Entries.save(ctx, record) ? :updated : false
      else
        record = scope.new(customer_id: ctx[:customer_id], entity_id: target.id)
        Entries.assign(record, row)
        Entries.save(ctx, record) ? :created : false
      end
    end

    def collect_row_error(ctx, _outcome)
      message = Array(ctx[:errors]).last.to_s
      detail = Array(ctx[:error_details]).pop || {}
      ctx[:errors].delete(message) if ctx[:errors].is_a?(Array)
      message.presence || detail["message"].to_s
    end

    def mapped_row(raw, mappings)
      row = raw.respond_to?(:to_h) ? raw.to_h : {}
      row = row.stringify_keys if row.respond_to?(:stringify_keys)
      return row if mappings.blank?

      mappings.each_with_object({}) do |(src, dest), acc|
        next if src.to_s.empty? || dest.to_s.empty?

        acc[dest.to_s] = row[src.to_s]
      end
    end
    private_class_method :mapped_row, :import_entity, :write_row, :collect_row_error
  end
end
