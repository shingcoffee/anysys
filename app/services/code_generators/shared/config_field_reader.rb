# frozen_string_literal: true

module CodeGenerators
  module Shared
    module ConfigFieldReader
      def fetch_with_default(key, default)
        value = config[key]
        value.respond_to?(:empty?) && value.empty? ? default : (value.nil? ? default : value)
      end

      # Like #fetch_with_default, but the value must be a bare Ruby identifier.
      # Use this for every config key whose value is spliced into emitted
      # source as a name (`ctx[:#{x}]`, a local, a method call) rather than as
      # a quoted literal.
      def fetch_ident(key, default)
        value = fetch_with_default(key, default)
        CodeGenerators::Shared::IdentifierSanitizer::IDENT_RE.match?(value.to_s) &&
          !CodeGenerators::Shared::IdentifierSanitizer::RUBY_RESERVED.include?(value.to_s) ? value.to_s : default
      end

      def fetch_enum(key, allowed, default:)
        value = config[key]
        allowed.include?(value) ? value : default
      end

      def fetch_int_positive(key, default:)
        raw = config[key]
        n = raw.to_i
        n > 0 ? n : default
      end
    end
  end
end
