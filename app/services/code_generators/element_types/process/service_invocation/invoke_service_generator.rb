# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ServiceInvocation
        class InvokeServiceGenerator < BaseGenerator
          KEYWORD_NAME_RE = /\A[a-z_][a-zA-Z0-9_]*\z/
          CTX_REF_RE = /\Actx\[:[a-zA-Z_][a-zA-Z0-9_]*\]\z/

          generator_metadata do
            description "Calls an allow-listed application service as Service.call(**kwargs) and stores " \
                        "the return value on resultVar (default service_result). Use this for a domain " \
                        "service such as a payment write-back or module caster; use send_email, " \
                        "request_payment, or the HTTP actions for those jobs. Keyword values are ctx " \
                        "paths (order.total) or literals. passContext adds ctx: ctx. A Result with " \
                        "ok or success? false copies its errors onto the submitter and fails the step; " \
                        "Invocable and argument errors fail as invoke_service.failed. False or nil " \
                        "returns stay on resultVar and the step succeeds."
            category :service_invocation
            version "4.0.0"
            presentation icon: "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z",
                         color: "purple", single_use: false, privileged: false
          end

          config_schema do
            reference :serviceClass, source: :service_classes, required: true, example: "FeatureModules::InputCaster",
                      placeholder: true,
                      description: "Allow-listed Ruby class that defines self.call(**kwargs) under app/, " \
                                   "such as FeatureModules::InputCaster or Payments::HandoffCompletion. " \
                                   "ActiveRecord models and classes without call are rejected."
            mapping :kwargs, key: :literal, value: :literal, default: [],
                    description: "Keyword arguments for call. Each key is a Ruby keyword (input, customer). " \
                                 "Each value is a ctx path (order.total) or a literal (true, 2, queued)."
            output :resultVar, default: "service_result", placeholder: true,
                   description: "Ctx variable that receives the return value, including a failed Result " \
                                "object. Default service_result. Later steps read this name."
            flag :passContext, default: false, group: :advanced,
                 description: "When true, also pass ctx: ctx so the service can read tenant and request " \
                              "keys. The service must accept that keyword. Default false."
            validate do |cfg, errors|
              name = cfg["serviceClass"].to_s
              if name.present?
                errors.add(:serviceClass, :invalid_class_name) unless FlowchartRuntime::Invocable.valid_const_name?(name)
                errors.add(:serviceClass, :not_allowlisted) unless FlowchartRuntime::Invocable.allowlisted_service?(name)
                klass = name.safe_constantize
                errors.add(:serviceClass, :active_record_class) if klass.is_a?(Class) && klass < ActiveRecord::Base
                if klass.is_a?(Class) && !(klass < ActiveRecord::Base)
                  begin
                    FlowchartRuntime::Invocable.method!(klass, "call", style: "call")
                  rescue FlowchartRuntime::Invocable::Error
                    errors.add(:serviceClass, :missing_call)
                  end
                end
              end

              Array(cfg["kwargs"]).each do |row|
                next unless row.is_a?(Hash)

                key = row["key"] || row[:key]
                next if key.to_s.empty?

                errors.add(:kwargs, :invalid_keyword, name: key) unless KEYWORD_NAME_RE.match?(key.to_s)
              end
            end
          end

          def generate_body
            attempt('"invoke_service.failed"', FlowchartRuntime::Invocable::Error) do
              [
                "service = FlowchartRuntime::Invocable.service!(#{read(:serviceClass)})",
                "result = FlowchartRuntime::Invocable.call!(service#{call_kwargs})",
                "next FlowchartRuntime::Invocable.fail_result(ctx, result) if FlowchartRuntime::Invocable.failed?(result)",
                assign(:resultVar, "result"),
                "true"
              ]
            end
          end

          private

          def call_kwargs
            parts = keyword_args
            parts << "ctx: ctx" if value(:passContext)
            parts.empty? ? "" : ", #{parts.join(', ')}"
          end

          def keyword_args
            mapping_rows(:kwargs).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next unless KEYWORD_NAME_RE.match?(key.to_s)

              "#{key}: #{argument_expression(row_value(row))}"
            end
          end

          def mapping_rows(name)
            raw = value(name)
            case raw
            when Hash then raw.map { |key, val| { "key" => key.to_s, "value" => val } }
            when Array then raw
            else []
            end
          end

          def row_value(row)
            return row unless row.is_a?(Hash)

            key = %w[sourceVariable value].flat_map { |name| [name, name.to_sym] }.find { |name| row.key?(name) }
            key ? row[key] : nil
          end

          def argument_expression(raw)
            return raw.inspect if raw.nil? || raw == true || raw == false || raw.is_a?(Numeric)

            src = raw.to_s
            return input_path(src.delete_prefix("ctx.")) if src.start_with?("ctx.")
            return src if CTX_REF_RE.match?(src)
            return input_path(src) if src.match?(/\A[a-z_][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)*\z/)

            src.inspect
          end

          def input_path(path)
            root, *rest = path.to_s.split(".", -1)
            return "nil" if root.to_s.empty?
            return "ctx[:#{root}]" if rest.empty? && safe_ident?(root)

            keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
            "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
          end
        end
      end
    end
  end
end
