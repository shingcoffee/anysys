# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped batch mutations over a source relation ANDed with Entries.scoped.
  module Batch
    class Error < StandardError; end

    module_function

    def run(ctx, source:, operation:, batch_size:, conditions: nil, assignments: {}, collect_errors: false,
            max_records: nil, stop_on_error: false, entity: nil, record_scope: "all")
      relation = begin
        intersect(ctx, source, entity: entity, record_scope: record_scope)
      rescue Entries::Error
        return Step.fail(ctx, :"batch_operation.entity_not_accessible")
      end
      relation = Entries.apply_conditions(relation, conditions, ctx)
      size = [batch_size.to_i, 1].max
      processed = 0
      cap = max_records.to_i
      stop = stop_on_error && collect_errors

      case operation.to_s
      when "update_all", "destroy_all"
        relation.in_batches(of: size).each_record do |record|
          break if cap.positive? && processed >= cap

          wrap(ctx, collect_errors) do
            if write(ctx, operation.to_s, record, assignments)
              processed += 1
            else
              return false unless collect_errors

              collect_failure(ctx)
            end
          end
          break if stop && ctx[:_batch_errors].present?
        end
      when "in_batches"
        relation.in_batches(of: size).each_record do |record|
          break if cap.positive? && processed >= cap

          wrap(ctx, collect_errors) do
            yield record if block_given?
            processed += 1
          end
          break if stop && ctx[:_batch_errors].present?
        end
      when "each_batch"
        relation.in_batches(of: size) do |batch_rel|
          break if cap.positive? && processed >= cap

          batch_rel = batch_rel.limit(cap - processed) if cap.positive?
          wrap(ctx, collect_errors) do
            yield batch_rel if block_given?
            processed += batch_rel.size
          end
          break if stop && ctx[:_batch_errors].present?
        end
      else
        relation.find_each(batch_size: size) do |record|
          break if cap.positive? && processed >= cap

          wrap(ctx, collect_errors) do
            yield record if block_given?
            processed += 1
          end
          break if stop && ctx[:_batch_errors].present?
        end
      end

      processed
    end

    def intersect(ctx, source, entity: nil, record_scope: "all")
      base = Entries.scoped(ctx, entity: entity, record_scope: record_scope)
      return base unless source.respond_to?(:and)

      source.and(base)
    rescue ArgumentError
      raise Error, "incompatible_scope"
    end

    def wrap(ctx, collect_errors)
      yield
    rescue Error
      raise
    rescue => error
      raise unless collect_errors

      ctx[:_batch_errors] ||= []
      ctx[:_batch_errors] << { message: error.message, class: error.class.name, at: Time.current }
    end

    def write(ctx, operation, record, assignments)
      return Entries.destroy(ctx, record) if operation == "destroy_all"

      Entries.assign(record, assignments, strict: true)
      Entries.save(ctx, record)
    end

    # A collected write failure must not also fail the step, so its Step.fail entry moves here.
    def collect_failure(ctx)
      detail = Array(ctx[:error_details]).pop || {}
      ctx[:errors].delete(detail["message"]) if ctx[:errors].is_a?(Array)
      ctx[:_batch_errors] ||= []
      ctx[:_batch_errors] << { message: detail["message"].to_s, class: detail["code"].to_s, at: Time.current }
    end

    private_class_method :intersect, :wrap, :write, :collect_failure
  end
end
