# frozen_string_literal: true

module Member
  # Per-tenant overlay for one Member::Surface descriptor.
  # The descriptor declares the maximum capability; this row narrows it
  # (visibility, label, icon, subtitle, position, page size, visible columns,
  # visible detail rows / sections, empty-state copy override).
  #
  # Anything that can be re-shaped without a schema change lives in `config`
  # as a JSON blob — same idiom as Captcha::ProviderSettings#config.
  class SurfaceSetting < ApplicationRecord
    self.table_name = "member_surface_settings"

    include JsonSerializable

    belongs_to :customer
    json_attribute :config, default: {}

    OMITTED = Object.new.freeze
    VISIBILITY_KEYS = %i[visible_column_keys visible_detail_row_keys visible_section_keys].freeze

    validates :surface_key, presence: true,
                            uniqueness: { scope: :customer_id }

    validates :source_key, presence: true,
                           inclusion: {
                             in: ->(_) { Member::Surfaces::SourceRegistry.all.map { |s| s.key.to_s } }
                           }

    def self.for_customer_surface(customer_id:, surface_key:)
      scope = where(customer_id: customer_id, surface_key: surface_key.to_s)
      scope.first || scope.new
    end

    # ---- Overlay accessors. *_or returns the override or the supplied default
    # when no override is set; the same surface a NullSurfaceSetting offers, so
    # EffectiveSurface can hand the same message off to either object. ----

    def enabled_or(default)        = enabled.nil? ? default : enabled
    def label_or(default)          = config_value(:label).presence    || default
    def icon_or(default)           = (config_value(:icon).presence || default).to_sym
    def subtitle_or(default)       = config_value(:subtitle).presence || default
    def empty_headline_or(default) = config_value(:empty_headline).presence || default
    def empty_body_or(default)     = config_value(:empty_body).presence || default

    def per_page_or(default)
      raw = config_value(:per_page).to_i
      raw.positive? ? raw : default
    end

    def position_or(default) = position.to_i.zero? ? default : position.to_i

    def row_action_or(default_label)
      key = config_value(:row_action_key).to_s
      field = config_value(:row_action_field).to_s
      return if key.blank? || field.blank?

      {
        action_key: key,
        field: field,
        label: config_value(:row_action_label).presence || default_label
      }
    end

    def visible_column_keys
      visibility_keys(:visible_column_keys)
    end

    def visible_detail_row_keys
      visibility_keys(:visible_detail_row_keys)
    end

    def visible_section_keys
      visibility_keys(:visible_section_keys)
    end

    # Omitted = preserve; nil = inherit. A visibility [] hides every optional
    # choice. Explicit blank display copy removes its override.
    def write_overlay(label: OMITTED, icon: OMITTED, subtitle: OMITTED,
                      empty_headline: OMITTED, empty_body: OMITTED,
                      per_page: OMITTED,
                      visible_column_keys: OMITTED,
                      visible_detail_row_keys: OMITTED,
                      visible_section_keys: OMITTED,
                      row_action_key: OMITTED,
                      row_action_field: OMITTED,
                      row_action_label: OMITTED)
      next_config = (config_json || {}).dup
      { label: label, icon: icon, subtitle: subtitle,
        empty_headline: empty_headline, empty_body: empty_body, per_page: per_page,
        visible_column_keys: visible_column_keys, visible_detail_row_keys: visible_detail_row_keys,
        visible_section_keys: visible_section_keys,
        row_action_key: row_action_key, row_action_field: row_action_field,
        row_action_label: row_action_label }.each do |key, value|
        next if value.equal?(OMITTED)

        if value.nil? || (!VISIBILITY_KEYS.include?(key) && value.blank?)
          next_config.delete(key.to_s)
        else
          next_config[key.to_s] = if VISIBILITY_KEYS.include?(key)
            Array(value).compact_blank.map(&:to_s)
          elsif key == :per_page
            value.to_i
          elsif key == :icon
            value.to_s
          else
            value
          end
        end
      end
      self.config_json = next_config
    end

    private

    def config_value(key) = (config_json || {})[key.to_s]

    def visibility_keys(key)
      value = config_value(key)
      value.nil? ? nil : Array(value).compact_blank.map(&:to_sym)
    end
  end
end
