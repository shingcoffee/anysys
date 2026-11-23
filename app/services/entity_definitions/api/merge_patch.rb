# frozen_string_literal: true

module EntityDefinitions
  module Api
    # RFC 7396 JSON Merge Patch. Objects merge, arrays replace, null deletes
    # an optional key. Used by update_entity `set` fields.
    module MergePatch
      module_function

      def apply(target, patch)
        patch = stringify(patch)
        return patch unless patch.is_a?(Hash)

        result = stringify(target)
        patch.each do |key, value|
          if value.nil?
            result.delete(key)
          elsif value.is_a?(Hash) && result[key].is_a?(Hash)
            result[key] = apply(result[key], value)
          else
            result[key] = value
          end
        end
        result
      end

      def stringify(value)
        case value
        when Hash then value.to_h.transform_keys(&:to_s).transform_values { |item| stringify(item) }
        when Array then value.map { |item| stringify(item) }
        else value
        end
      end
    end
  end
end
