# frozen_string_literal: true

module CodeGenerators
  module Shared
    module ConditionBuilder
      include CodeGenerators::Shared::OperandConverter

      def build_structured_condition(condition)
        return "true" if condition.blank?

        if condition["type"] == "group"
          build_condition_group(condition)
        else
          build_single_condition(condition)
        end
      end

      def build_query_count_condition(condition)
        query_config = condition["queryConfig"] || {}
        entity_id = query_config["entityId"]
        where_conditions = query_config["conditions"]
        count_op = condition["countOperator"].to_s
        raise ArgumentError, "unknown count operator: #{count_op.inspect}" unless CodeGenerators::ConditionOperators.count?(count_op)
        count_val = condition["countValue"] || 0

        parts = []
        parts << "FlowchartRuntime::QueryBuilder.for_entity(FlowchartRuntime::EntityResolver.find(#{entity_id.to_i}, customer_id: ctx[:customer_id]), customer_id: ctx[:customer_id])"

        if where_conditions.is_a?(Hash) && where_conditions["rules"].present?
          parts << "  .where(#{where_conditions.inspect}, ctx)"
        end

        parts << "  .execute.total_count #{count_op} #{count_val.to_i}"
        parts.join("\n")
      end

      def group_conditions(condition)
        return [] unless condition.is_a?(Hash)
        condition["type"] == "group" ? (condition["conditions"] || []) : [condition]
      end

      private

      def build_condition_group(group)
        conditions = group["conditions"] || []
        return "true" if conditions.empty?

        joins = group["joins"]
        joins = [] unless joins.is_a?(Array)

        parts = conditions.map { |c| build_group_member(c) }.reject(&:blank?)
        return "true" if parts.empty?

        expr = parts.first
        parts.each_with_index do |part, i|
          next if i.zero?
          expr = "(#{expr} #{ruby_join_operator(joins[i - 1])} #{part})"
        end
        expr
      end

      def build_group_member(member)
        if CodeGenerators::ConditionRules.query_count_row?(member)
          build_query_count_condition(member)
        elsif member["type"] == "group"
          raise ArgumentError, "nested condition groups are not allowed"
        else
          build_single_condition(member)
        end
      end

      def ruby_join_operator(join)
        join.to_s.upcase == "OR" ? "||" : "&&"
      end

      # A defensive allowlist of types accepted by the `is_type` operator.
      # Only bare constant identifiers match — anything else is coerced to
      # false so the generated Ruby cannot raise `TypeError` or reference
      # surprising constants at runtime.
      IS_TYPE_ALLOWED = %w[
        String Integer Float Numeric Array Hash Symbol TrueClass FalseClass
        NilClass Regexp Time Date DateTime Range BigDecimal Complex Rational
      ].freeze

      def build_single_condition(condition)
        raw_left  = condition["leftOperand"]
        raw_right = condition["rightOperand"]
        left      = condition_operand_to_ruby(raw_left)
        operator  = condition["operator"].to_s
        right     = condition_operand_to_ruby(raw_right)

        unless CodeGenerators::ConditionOperators.known?(operator)
          raise ArgumentError, "unknown condition operator: #{operator.inspect}"
        end

        case operator
        when "is_empty"      then return "#{left}.blank?"
        when "is_not_empty"  then return "#{left}.present?"
        when "is_true"       then return "!!#{left}"
        when "is_false"      then return "!#{left}"
        when "is_nil"        then return "#{left}.nil?"
        when "matches_regex"
          # A nil / blank right operand makes `match?(nil)` raise TypeError
          # at runtime. Fall back to `false` so the generated code stays
          # well-defined even when the flowchart author hasn't (yet) filled
          # in the pattern.
          return "false" if raw_right.blank?
          pattern = raw_right.to_s
          begin
            regexp = Regexp.new(pattern)
          rescue RegexpError
            return "false"
          end
          return "#{left}.to_s.match?(#{regexp.inspect})"
        when "in_range"      then return "(#{right}).include?(#{left})"
        when "is_type"
          # `right` was already quoted by condition_operand_to_ruby, which
          # makes `is_a?("Integer")` — always TypeError. Pull the raw
          # operand and accept it only if it's a known constant identifier.
          type_name = raw_right.to_s.strip
          return "false" unless IS_TYPE_ALLOWED.include?(type_name)
          return "#{left}.is_a?(#{type_name})"
        end

        ruby_op = case operator
        when "==" then "=="
        when "!=" then "!="
        when ">", ">=", "<", "<="
          return "FlowchartRuntime::ConditionInput.compare(#{left}, #{operator.inspect}, #{right})"
        when "contains"    then return "#{left}.to_s.include?(#{right}.to_s)"
        when "starts_with" then return "#{left}.to_s.start_with?(#{right}.to_s)"
        when "ends_with"   then return "#{left}.to_s.end_with?(#{right}.to_s)"
        else
          raise ArgumentError, "unknown condition operator: #{operator.inspect}"
        end

        "#{left} #{ruby_op} #{right}"
      end
    end
  end
end
