# frozen_string_literal: true

module FlowchartRuntime
  # Picks one candidate from a pool for select_assignee. Round-robin rotation
  # is a tenant-scoped Sequence counter, never a process-global variable.
  module Assignment
    class Error < StandardError; end

    STRATEGIES = %w[round_robin random weighted least_loaded first].freeze
    SOURCES = %w[variable role].freeze
    ROLES = %w[admin member].freeze
    SEQUENCE_PREFIX = "select_assignee:"

    module_function

    def pick(ctx, candidates, strategy:, pool_key: "default", weight_field: "weight",
             load_field: "open_items", availability_field: nil, exclude: nil,
             id_field: "id", returns: "candidate")
      mode = strategy.to_s
      raise Error, "unknown strategy #{strategy.inspect}" unless STRATEGIES.include?(mode)

      eligible = filter_candidates(candidates, availability_field, exclude, id_field)
      return nil if eligible.empty?

      chosen = case mode
      when "round_robin" then round_robin(ctx, eligible, pool_key)
      when "random" then eligible[SecureRandom.random_number(eligible.size)]
      when "weighted" then weighted(eligible, weight_field)
      when "least_loaded" then least_loaded(eligible, load_field)
      else eligible.first
      end
      return nil if chosen.nil?

      returns.to_s == "id" ? candidate_id(chosen, id_field) : chosen
    end

    # Active users of this tenant who hold the reserved +role+ (admin or
    # member). Owner is never included. Empty when customer_id is missing.
    def users_of_role(ctx, role)
      customer_id = ctx && ctx[:customer_id]
      return [] if customer_id.blank?

      key = role.to_s
      return [] unless ROLES.include?(key)

      ::Authentication::User.where(customer_id: customer_id).active.by_role(key).to_a
    end

    def filter_candidates(candidates, availability_field, exclude, id_field)
      excluded = normalize_list(exclude).map { |item| item.to_s }
      Array(candidates).select do |item|
        next false unless available?(item, availability_field)

        excluded.exclude?(candidate_id(item, id_field).to_s)
      end
    end

    def round_robin(ctx, eligible, pool_key)
      name = "#{SEQUENCE_PREFIX}#{pool_key}"
      ordinal = Sequence.next(ctx, name: name, period: "never", prefix: "", padding: 1).to_i
      eligible[(ordinal - 1) % eligible.size]
    rescue Sequence::Error => error
      raise Error, error.message
    end

    def weighted(eligible, field)
      weights = eligible.map { |item| [item, numeric(field_value(item, field))] }
      total = weights.sum(&:last)
      return eligible.first if total <= 0

      pick = SecureRandom.random_number * total
      running = 0.0
      weights.each do |item, weight|
        running += weight
        return item if pick < running
      end
      weights.last.first
    end

    def least_loaded(eligible, field)
      eligible.min_by { |item| numeric(field_value(item, field)) }
    end

    def candidate_id(item, id_field)
      return item unless structured?(item)

      field_value(item, id_field)
    end

    def available?(item, field)
      return true if field.to_s.empty?

      ActiveModel::Type::Boolean.new.cast(field_value(item, field)) == true
    end

    def field_value(item, field)
      return if field.to_s.empty? || !structured?(item)

      if item.is_a?(ActiveRecord::Base) && item.has_attribute?(field)
        return item.read_attribute(field)
      end

      Collections.dig_item(item, field)
    end

    def structured?(item)
      item.is_a?(Hash) || item.is_a?(ActiveRecord::Base)
    end

    def numeric(value)
      return 0.0 if value.nil?

      value.is_a?(Numeric) ? value.to_f : Float(value)
    rescue ArgumentError, TypeError
      0.0
    end

    def normalize_list(value)
      case value
      when nil then []
      when Array then value
      else [value]
      end
    end

    private_class_method :filter_candidates, :round_robin, :weighted, :least_loaded,
      :candidate_id, :available?, :field_value, :structured?, :numeric, :normalize_list
  end
end
