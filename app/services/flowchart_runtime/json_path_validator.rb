# frozen_string_literal: true

module FlowchartRuntime
  # JsonPathValidator
  #
  # Allowlist guard for JSON path segments interpolated into raw SQL
  # (json_extract expressions). Rejects any key that is not a plain
  # identifier or dot-separated chain of identifiers, preventing SQL
  # injection via user-supplied field keys in page configuration JSON.
  #
  # Valid:   "name", "billing_address", "contact.phone_number"
  # Invalid: "name')) OR 1=1 --", "'; DROP TABLE--", "a b"
  module JsonPathValidator
    class Error < ArgumentError; end

    # Matches a single identifier or a dot-separated chain of identifiers.
    # Each segment is one or more letters, digits, or underscores —
    # digit-leading segments are allowed because String#parameterize legitimately
    # produces them for attribute names starting with a number (e.g. "2024_revenue").
    SAFE_JSON_PATH_RE = /\A\w+(\.\w+)*\z/

    module_function

    # Validate that +path+ is a safe JSON key/path for interpolation.
    #
    # @param path [String] the field key or dot-path to validate
    # @return [String] the original path when safe
    # @raise [ArgumentError] when the path contains characters outside the allowlist
    def safe_json_path!(path)
      path = path.to_s
      unless path.match?(SAFE_JSON_PATH_RE)
        raise Error,
          "Unsafe JSON path rejected (contains disallowed characters): #{path.inspect}"
      end
      path
    end
  end
end
