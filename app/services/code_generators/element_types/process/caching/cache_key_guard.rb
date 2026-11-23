# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        # Generation-time CacheKey.scoped rules (no wildcards, ≤ 200 bytes).
        module CacheKeyGuard
          module_function

          def validate(cfg, errors, *fields)
            fields.each do |name|
              token = cfg[name.to_s].to_s
              next if token.strip.empty?

              errors.add(name, :wildcard) if token.match?(FlowchartRuntime::CacheKey::WILDCARD_RE)
              if token.bytesize > FlowchartRuntime::CacheKey::MAX_PART_BYTES
                errors.add(name, :too_long, max_length: FlowchartRuntime::CacheKey::MAX_PART_BYTES)
              end
            end
          end
        end
      end
    end
  end
end
