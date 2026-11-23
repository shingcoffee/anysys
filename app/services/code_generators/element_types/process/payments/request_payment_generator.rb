# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Payments
        class RequestPaymentGenerator < BaseGenerator
          EXIT_KINDS = %w[none page url route record].freeze
          MAPPING_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
          PAID_SLOTS = %w[paidAtField paymentReferenceField].freeze
          CURRENCY_FORMAT = /\A[A-Z]{3}\z/

          generator_metadata do
            description "Hands off to checkout after the submission, which creates the payment order. Put this after everything it charges for is saved. amount is the saved total (ctx[:model].total); currency is ISO 4217 (CNY). paidRecord is the record paid for (blank for the page record); paidFields are set on it once payment succeeds, each value one of that field's options. Use refund_payment to give money back and set_submission_outcome for flash copy (it preserves this handoff). Parks the handoff on ctx[:submission_outcome]. Refuses invalid_order, module_disabled, invalid_paid_record, or invalid_paid_field."
            category :payments
            version "1.3.0"
            presentation icon: "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
                        color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            expression :amount, required: true, example: 'BigDecimal("10.00")',
                       description: "Ruby expression for the order amount in major units, such as ctx[:model].total or ctx[:pricing][\"total\"]. Use a decimal string or BigDecimal, not a Float literal (10.00). Must be positive after currency rounding (CNY 2 decimals)."
            literal :currency, default: "CNY", example: "CNY",
                    description: "ISO 4217 currency code as three uppercase letters, such as CNY. Checkout currently charges in CNY. Do not write a Ruby expression here."
            expression :subject, required: true, example: '"Registration fee"',
                       description: "Ruby expression for the order subject shown at checkout, such as \"Registration fee\" or \"Payment \" + ctx[:model].reference_number.to_s. Must evaluate to a non-blank string."
            expression :description, example: '"Payer note"',
                       description: "Optional Ruby expression for a payer note stored on the order as body, such as \"Payer note\" or ctx[:model].note. Leave blank to omit."
            expression :paidRecord,
                       description: "Ruby expression for the saved EntityEntry this payment is for, such as ctx[:referenced_record]. Leave blank for the page's own record (ctx[:model]). Must already be persisted for this customer."
            mapping :paidFields, key: :literal, value: :literal, default: [],
                    description: "Fields set on the record paid for once payment succeeds. Each key is a writable slug (status) and each value is stored as typed, exactly one of that field's options when the field is a select (Paid). Nothing is written until payment succeeds; never also set those fields with update_model."
            literal :paidAtField,
                    description: "Optional date or time field slug on the record paid for that receives the payment time, such as paid_on. Leave blank to skip. Must be a writable stored field, not calculated."
            literal :paymentReferenceField,
                    description: "Optional text field slug on the record paid for that receives the payment reference, such as payment_reference. Leave blank to skip. Must be a writable stored field."
            mapping :metadata, key: :literal, value: :expression, default: [], group: :advanced,
                    description: "Optional key/value pairs stored on the order. Each key is a name (sku) and each value is a Ruby expression over ctx (\"abc\" or ctx[:sku])."
            integer :expiresInMinutes, min: 1, max: 10_080, group: :advanced,
                    description: "Minutes until the checkout order expires, from 1 to 10080 (7 days). Leave blank for no expiry. Converted to an UTC expires_at timestamp at run time."
            enum :exitKind, EXIT_KINDS, default: "none", group: :advanced,
                 description: "Where to send the visitor when checkout finishes. none uses the default landing. page opens exitPage. url opens exitUrl. route opens exitRoute. record opens the record paid for (requires that record to be saved)."
            reference :exitPage, source: :pages, example: 1, visible: { exitKind: "page" }, group: :advanced,
                      description: "Launched page of this customer to open when checkout finishes. Required when exitKind is page."
            literal :exitUrl, example: "https://example.test", placeholder: true,
                    visible: { exitKind: "url" }, group: :advanced,
                    description: "http or https URL to open when checkout finishes, such as https://example.test. javascript: and other schemes are rejected."
            literal :exitRoute, example: "customer_home", placeholder: true,
                    visible: { exitKind: "route" }, group: :advanced,
                    description: "Named Rails route to open when checkout finishes, such as customer_home. Required when exitKind is route."
            requires :exitPage, when: { exitKind: "page" }
            requires :exitUrl, when: { exitKind: "url" }
            requires :exitRoute, when: { exitKind: "route" }
            validate do |cfg, errors|
              code = cfg["currency"].to_s.strip.upcase
              errors.add(:currency, :invalid_currency) unless code.empty? || CURRENCY_FORMAT.match?(code)

              slugs = PAID_SLOTS.to_h { |name| [name, cfg[name].to_s.strip] }.reject { |_, slug| slug.empty? }
              rows = Array(cfg["paidFields"]).select { |row| row.is_a?(Hash) }
              keys = rows.map { |row| (row["key"] || row[:key]).to_s.strip }.reject(&:empty?)
              slugs.each do |name, slug|
                errors.add(name.to_sym, :invalid_identifier) unless ConfigSchema::IDENT_SEGMENT.match?(slug)
              end
              errors.add(:paidFields, :invalid_identifier) unless keys.all? { |key| ConfigSchema::IDENT_SEGMENT.match?(key) }
              next unless respond_to?(:paid_page_entity, true) && (entity = paid_page_entity(cfg))

              writable = RequestPaymentGenerator.writable_slugs(entity)
              (keys + slugs.values).uniq.reject { |slug| writable.include?(slug) }.each do |slug|
                errors.add(:paidFields, :not_a_field, attribute: slug, entity: entity.try(:display_label) || entity.try(:name))
              end
              rows.each do |row|
                slug = (row["key"] || row[:key]).to_s.strip
                next if slug.empty? || !writable.include?(slug)

                allowed = RequestPaymentGenerator.option_values(entity, slug)
                next if allowed.nil?

                chosen = (row["value"] || row[:value]).to_s
                next if allowed.include?(chosen)

                errors.add(:paidFields, :invalid_option, attribute: slug, value: chosen)
              end
            end
            validate do |cfg, errors|
              next unless cfg["exitKind"].to_s == "url"

              url = cfg["exitUrl"].to_s.strip
              next if url.empty?

              uri = URI.parse(url)
              errors.add(:exitUrl, :invalid_url) unless %w[http https].include?(uri.scheme)
            rescue URI::InvalidURIError
              errors.add(:exitUrl, :invalid_url)
            end
          end

          # Fields a payment may set on a record: stored ones, never derived.
          def self.writable_slugs(entity)
            Array(entity.property_schema_json).filter_map do |row|
              next unless row.is_a?(Hash) && !%w[Calculated Computed].include?(row["type"])

              row["name_slug"].to_s.presence
            end
          end

          # Static option values of a select/radio field, or nil when the field
          # is free text so any string may be written.
          def self.option_values(entity, slug)
            row = Array(entity.property_schema_json).grep(Hash).find { |item| item["name_slug"].to_s == slug }
            return unless row

            settings = row["config"].is_a?(Hash) ? row["config"] : {}
            return unless settings["source"].to_s.in?(["manual", ""]) &&
                          settings["options_source"].to_s.in?(["", "manual"]) &&
                          settings["options_entity_name"].blank? && settings["entity_id"].blank? &&
                          settings["constant_id"].blank? && settings["constant_name"].blank?

            values = Array(settings["options"]).grep(Hash).filter_map do |option|
              option["value"].to_s.strip.presence || option["label"].to_s.strip.presence
            end
            values.presence
          end

          def generate_body
            body("FlowchartRuntime::Payments.request(ctx, #{request_args})")
          end

          private

          def request_args
            parts = [
              "amount: #{read(:amount)}",
              "currency: #{currency_literal}",
              "subject: #{read(:subject)}"
            ]
            parts << "description: #{read(:description)}" if value(:description).to_s.strip.present?
            mapping = expression_mapping(:metadata)
            parts << "metadata: #{mapping}" unless mapping == "{}"
            parts << "expires_in_minutes: #{read(:expiresInMinutes)}" if value(:expiresInMinutes).present?
            parts.concat(paid_args)
            target = exit_target_literal
            parts << "exit_target: #{target}" if target
            parts.join(", ")
          end

          def currency_literal
            code = value(:currency).to_s.strip.upcase
            (CURRENCY_FORMAT.match?(code) ? code : "CNY").inspect
          end

          def paid_args
            parts = []
            parts << "paid_record: #{read(:paidRecord)}" if value(:paidRecord).to_s.strip.present?
            fields = Array(value(:paidFields)).filter_map do |row|
              key = row.is_a?(Hash) ? (row["key"] || row[:key]).to_s.strip : ""
              [key, (row["value"] || row[:value]).to_s] if MAPPING_NAME.match?(key)
            end
            parts << "paid_fields: #{literal(fields.to_h)}" if fields.any?
            parts << "paid_at_field: #{read(:paidAtField)}" if value(:paidAtField).to_s.strip.present?
            parts << "reference_field: #{read(:paymentReferenceField)}" if value(:paymentReferenceField).to_s.strip.present?
            parts
          end

          def exit_target_literal
            case value(:exitKind)
            when "page"
              %({"kind" => "page", "page_id" => #{read(:exitPage)}})
            when "url"
              %({"kind" => "url", "url" => #{read(:exitUrl)}})
            when "route"
              %({"kind" => "route", "name" => #{read(:exitRoute)}})
            when "record"
              %({"kind" => "record"})
            end
          end

          # The page's own entity, when the step pays for the page record.
          def paid_page_entity(cfg)
            record = cfg["paidRecord"].to_s.strip
            return unless record.empty? || record == "ctx[:model]"

            entity = if context.respond_to?(:bound_entity) then context.bound_entity
                     elsif context.is_a?(Hash) then context[:bound_entity] || context["bound_entity"]
                     end
            entity if entity.respond_to?(:property_schema_json)
          end

          def expression_mapping(field_name)
            pairs = safe_expression_pairs(value(field_name)).filter_map do |name, expression|
              next unless name.match?(MAPPING_NAME)

              "#{literal(name)} => #{emit_expression(expression)}"
            end
            return "{}" if pairs.empty?

            "{#{pairs.join(', ')}}"
          end
        end
      end
    end
  end
end
