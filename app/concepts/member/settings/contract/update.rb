# frozen_string_literal: true

module Member
  module Settings
    module Contract
      class Update < Reform::Form
        # The form binds to a wrapper struct that exposes a `rows` collection.
        # Each row corresponds to one descriptor surface's settings overlay.
        collection :rows, populate_if_empty: OpenStruct do
          property :surface_key
          property :enabled,                 virtual: true
          property :position,                virtual: true
          property :label,                   virtual: true
          property :icon,                    virtual: true
          property :subtitle,                virtual: true
          property :empty_headline,          virtual: true
          property :empty_body,              virtual: true
          property :per_page,                virtual: true
          property :visible_column_keys,     virtual: true
          property :visible_detail_row_keys, virtual: true
          property :visible_section_keys,    virtual: true
          property :row_action_key,          virtual: true
          property :row_action_field,        virtual: true
          property :row_action_label,        virtual: true

          MAX_VISIBLE_KEYS = 50
          MAX_ROW_ACTION_LABEL = 60

          validates :surface_key, presence: true
          validates :per_page,
                    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 200 },
                    allow_blank: true
          validates :position,
                    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                    allow_blank: true
          validates :row_action_key, format: { with: PageVisibility::ACTION_KEY }, allow_blank: true
          validates :row_action_field, format: { with: Pages::FormParams::SLUG }, allow_blank: true
          validates :row_action_label, length: { maximum: MAX_ROW_ACTION_LABEL }, allow_blank: true
          validate :visible_keys_within_bounds
          validate :row_action_pair_present

          def visible_keys_within_bounds
            %i[visible_column_keys visible_detail_row_keys visible_section_keys].each do |attr|
              value = public_send(attr)
              next if value.nil?
              if Array(value).size > MAX_VISIBLE_KEYS
                errors.add(attr, I18n.t("admin_settings.errors.validations.visible_keys_max", count: MAX_VISIBLE_KEYS))
              end
            end
          end

          def row_action_pair_present
            key = row_action_key.to_s
            field = row_action_field.to_s
            return if key.blank? && field.blank?
            return if key.present? && field.present?

            message = I18n.t("admin_settings.errors.validations.row_action_invalid")
            errors.add(:row_action_key, message)
            errors.add(:row_action_field, message)
          end
        end
      end
    end
  end
end
