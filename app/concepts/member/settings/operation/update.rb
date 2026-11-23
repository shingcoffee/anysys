# frozen_string_literal: true

module Member
  module Settings
    module Operation
      class Update
        Result = Struct.new(:success?, :errors, keyword_init: true) do
          def [](k) = send(k)
        end

        OVERLAY_KEYS = %i[label icon subtitle empty_headline empty_body per_page
                          visible_column_keys visible_detail_row_keys visible_section_keys
                          row_action_key row_action_field row_action_label].freeze

        # @param customer [Customer]
        # @param params [ActionController::Parameters | Hash] expects { rows: [...] }
        def self.call(customer:, params:)
          payload = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
          raw_rows = payload[:rows] || payload["rows"]
          attributes_by_row = normalize_rows(raw_rows).map { |h|
            attributes = h.transform_keys(&:to_sym)
            # Remove hidden checkbox sentinels before validation; keep omissions nil.
            %i[visible_column_keys visible_detail_row_keys visible_section_keys].each do |key|
              next if attributes[key].nil?

              attributes[key] = Array(attributes[key]).compact_blank
            end
            attributes
          }

          rows = attributes_by_row.map { |attributes| OpenStruct.new(attributes) }
          form = ::Member::Settings::Contract::Update.new(OpenStruct.new(rows: rows))
          unless form.validate(rows: rows.map { |r| r.to_h.transform_keys(&:to_s) })
            return Result.new(success?: false, errors: form.errors)
          end

          customer.with_lock(requires_new: true) do
            # Resolve the entire batch before its first write. The customer
            # lock also serializes creation/overlay merges across these forms.
            edits = form.rows.zip(attributes_by_row).filter_map do |row, submitted|
              effective = Member::Surfaces.fetch(row.surface_key, customer: customer)
              source = Member::Surfaces.source_for(effective.source_key)
              next if source.nil? || !source.editable?

              [row, submitted, effective]
            end

            edits.each do |row, submitted, effective|
              setting = Member::SurfaceSetting.for_customer_surface(
                customer_id: customer.id, surface_key: row.surface_key
              )
              setting.source_key = effective.source_key.to_s
              setting.enabled    = truthy?(row.enabled) if submitted.key?(:enabled)
              setting.position   = row.position.to_i if row.position.present?
              overlay = OVERLAY_KEYS.each_with_object({}) do |key, values|
                next unless submitted.key?(key)

                value = row.public_send(key)
                values[key] = key == :per_page ? (value.presence && value.to_i) : value
              end
              setting.write_overlay(**overlay)
              setting.save!
            end
          end

          Result.new(success?: true, errors: nil)
        rescue ActiveRecord::RecordNotFound
          form.errors.add(:surface_key, I18n.t("admin_settings.errors.validations.invalid_surface"))
          Result.new(success?: false, errors: form.errors)
        rescue ActiveRecord::RecordInvalid => e
          Result.new(success?: false, errors: e.record.errors)
        end

        def self.truthy?(value)
          ActiveModel::Type::Boolean.new.cast(value) ? true : false
        end

        # Forms emit `rows[0][...]` which Rails parses to {"0" => {...}}; specs
        # may pass arrays directly. Normalize both into an array of hashes.
        def self.normalize_rows(raw)
          case raw
          when Array then raw.filter_map { |r| row_to_h(r) }
          when Hash  then raw.values.filter_map { |r| row_to_h(r) }
          else            []
          end
        end

        def self.row_to_h(row)
          return row.to_unsafe_h if row.respond_to?(:to_unsafe_h)
          return row.to_h if row.is_a?(Hash)

          nil
        end
        private_class_method :row_to_h
      end
    end
  end
end
