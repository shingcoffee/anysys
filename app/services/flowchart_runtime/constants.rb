# frozen_string_literal: true

module FlowchartRuntime
  # Reads Constant options for a run using ctx[:customer_id], never Current.
  # A shared constant uses that customer's override row when present.
  module Constants
    class Error < StandardError; end

    module_function

    def options(ctx, id)
      constant_id, owner_id, stored = load_constant!(ctx, id)
      if owner_id.nil?
        override = ConstantCustomerOverride.find_by(constant_id: constant_id, customer_id: ctx[:customer_id])
        return Array(override.options) if override
      end
      Array(stored)
    end

    def label(ctx, id, value, default: nil)
      match = options(ctx, id).find { |option| option_value(option).to_s == value.to_s }
      match ? option_label(match) : default
    end

    def load_constant!(ctx, id)
      raise Error, "customer is required" if ctx.nil? || ctx[:customer_id].blank?
      raise Error, "constant is required" if id.blank?

      key = id.to_s.strip
      row = if key.match?(/\A\d+\z/)
        Constant.where(id: key).pick(:id, :customer_id, :options)
      else
        Constant.where(name: key)
                .where("customer_id = ? OR customer_id IS NULL", ctx[:customer_id])
                .order(Arel.sql("customer_id IS NULL"))
                .pick(:id, :customer_id, :options)
      end
      raise Error, "constant is not accessible" unless row

      constant_id, owner_id, stored = row
      unless owner_id.nil? || owner_id.to_s == ctx[:customer_id].to_s
        raise Error, "constant is not accessible"
      end

      [constant_id, owner_id, stored]
    end

    def option_value(option)
      return option["value"] || option[:value] || option["label"] || option[:label] if option.is_a?(Hash)

      option
    end

    def option_label(option)
      return option["label"] || option[:label] || option["value"] || option[:value] if option.is_a?(Hash)

      option
    end
    private_class_method :load_constant!, :option_value, :option_label
  end
end
