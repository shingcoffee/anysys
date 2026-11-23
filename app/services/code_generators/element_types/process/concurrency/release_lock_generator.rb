# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Concurrency
        class ReleaseLockGenerator < BaseGenerator
          ON_MISSING = %w[ignore fail log].freeze
          SAFE_CTX_RE = /\Actx\[:([A-Za-z_][A-Za-z0-9_]*)\]\z/
          SAFE_SHORTHAND_RE = /\Actx:([A-Za-z_][A-Za-z0-9_]*)\z/

          generator_metadata do
            description "Releases the tenant-scoped lock taken by acquire_lock. When lockKey and lockKeyVariable are blank, reads ctx[:_cache_lock_key]; when holderIdentity is blank, reads ctx[:_lock_token] — matching acquire_lock defaults. Otherwise lockKey is a Liquid template or lockKeyVariable a ctx path, and holderIdentity is the token (or ctx[:name]). onMissing 'ignore' (default) succeeds even if this token does not hold the lock; 'fail' fails with release_lock.not_held; 'log' warns and succeeds. Fails with release_lock.failed on a blank key, blank token, or missing tenant. A lock that is never released expires at the acquire ttl."
            category :concurrency
            version "4.2.0"
            presentation icon: "M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            template :lockKey, example: "order:{{ model.id }}", placeholder: true,
              description: "Liquid lock name to release. Leave blank to use ctx[:_cache_lock_key] from acquire_lock. lockKeyVariable wins when set."
            input :lockKeyVariable,
              description: "ctx path holding the lock name, e.g. '_cache_lock_key'. When set, it wins over lockKey and the acquire_lock default."
            literal :holderIdentity, placeholder: true,
              description: "Holder token that must match the lock. Blank uses ctx[:_lock_token] from acquire_lock. A ctx[:name] path is also accepted."
            enum :onMissing, ON_MISSING, default: "ignore",
              description: "'ignore' (default) succeeds if this token does not hold the lock. 'fail' fails with release_lock.not_held. 'log' warns and succeeds."
            validate do |cfg, errors|
              holder = cfg["holderIdentity"].to_s
              if holder.include?("\n") || (holder.start_with?("ctx[") && !SAFE_CTX_RE.match?(holder))
                errors.add(:holderIdentity, :invalid_holder)
              end
            end
          end

          def generate_body
            release_call = "FlowchartRuntime::Lock.release(ctx[:customer_id], lock_key, holder)"
            lines = [
              "lock_key = #{lock_key_expr}",
              "holder = #{holder_expr}"
            ]
            case value(:onMissing)
            when "fail"
              lines << "released = #{release_call}"
              lines << fail_with('"release_lock.not_held"', unless: "released")
            when "log"
              lines << "released = #{release_call}"
              lines << 'Rails.logger.warn("release_lock.not_held") unless released'
            else
              lines << release_call
            end
            lines << "true"

            body(
              attempt(
                '"release_lock.failed"',
                FlowchartRuntime::Lock::Error,
                FlowchartRuntime::Template::Error
              ) { lines }
            )
          end

          private

          def lock_key_expr
            return "#{read(:lockKeyVariable)}.to_s" if value(:lockKeyVariable).to_s.strip.present?
            return read(:lockKey) if value(:lockKey).to_s.strip.present?

            "ctx[:_cache_lock_key]"
          end

          def holder_expr
            raw = value(:holderIdentity).to_s.strip
            return "ctx[:_lock_token]" if raw.empty?
            return "ctx[:#{Regexp.last_match(1)}]" if raw.match(SAFE_CTX_RE) || raw.match(SAFE_SHORTHAND_RE)

            read(:holderIdentity)
          end
        end
      end
    end
  end
end
