# frozen_string_literal: true

# Per-customer, per-entity overlay for the admin entity entries index columns.
# Preference lives in config["visible_column_keys"] (attribute name_slugs only).
# Key absent → nil (use defaults); key present as [] → no attribute columns.
class EntityIndexSetting < ApplicationRecord
  include JsonSerializable

  # Matches Member::Settings::Contract::Update — a crafted ?per_page= must not
  # persist or load unbounded row sets on the entity index.
  PER_PAGE_MAX = 200
  ALLOWED_DENSITIES = %w[comfortable compact].freeze

  belongs_to :customer
  belongs_to :entity

  json_attribute :config, default: {}

  validates :entity_id, uniqueness: { scope: :customer_id }

  def self.clamp_per_page(value, default: ModuleEntriesResolver::DEFAULT_PER_PAGE)
    n = value.to_i
    n.between?(1, PER_PAGE_MAX) ? n : default
  end

  def self.for(customer_id:, entity_id:)
    scope = where(customer_id: customer_id, entity_id: entity_id)
    scope.first || scope.new
  end

  def visible_column_keys
    cfg = config_json || {}
    return nil unless cfg.key?("visible_column_keys")

    Array(cfg["visible_column_keys"]).map(&:to_sym)
  end

  def write_overlay(visible_column_keys:)
    next_config = (config_json || {}).dup
    next_config["visible_column_keys"] = Array(visible_column_keys).map(&:to_s)
    self.config_json = next_config
  end

  def per_page
    v = (config_json || {})["per_page"]
    return nil if v.blank?

    n = v.to_i
    n.between?(1, PER_PAGE_MAX) ? n : nil
  end

  def density
    d = (config_json || {})["density"].presence
    ALLOWED_DENSITIES.include?(d) ? d : nil
  end

  def write_list_prefs(per_page: nil, density: nil)
    next_config = (config_json || {}).dup
    if !per_page.nil? && per_page.to_s.present?
      n = per_page.to_i
      next_config["per_page"] = n if n.between?(1, PER_PAGE_MAX)
    end
    if density.present?
      d = density.to_s
      next_config["density"] = d if ALLOWED_DENSITIES.include?(d)
    end
    self.config_json = next_config
  end
end
