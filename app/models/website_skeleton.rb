# frozen_string_literal: true

class WebsiteSkeleton < ApplicationRecord
  KEY_FORMAT = /\A[a-z0-9]+(?:_[a-z0-9]+)*\z/

  validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT }
  validates :name, presence: true
  validates :pages, presence: true
  validate :pages_structure_is_valid

  scope :active, -> { where(archived: false).order(:position, :id) }

  def theme_preset_key
    theme_key.presence || Websites::ThemePairing.for_skeleton(key)
  end

  def page_list
    Array(pages).map { |page| page.respond_to?(:stringify_keys) ? page.stringify_keys : page }
  end

  def display_name
    i18n_key = "website.skeletons.#{key}.name"
    I18n.exists?(i18n_key) ? I18n.t(i18n_key) : name
  end

  def display_description
    i18n_key = "website.skeletons.#{key}.description"
    I18n.exists?(i18n_key) ? I18n.t(i18n_key) : description.to_s
  end

  private

  def pages_structure_is_valid
    contract = Websites::Contracts::Skeleton.new(self)
    return if contract.validate({})

    contract.errors.each { |error| errors.add(error.attribute, error.message) }
  end
end
