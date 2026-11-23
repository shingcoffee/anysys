# frozen_string_literal: true

class WebsitePage < ApplicationRecord
  include TenantScoped

  RESERVED_SLUGS = %w[new edit preview site media].freeze

  belongs_to :website, inverse_of: :pages

  def layout
    return if layout_key.blank?

    WebsiteLayout.find_by(key: layout_key)
  end

  validates :customer_id, presence: true
  validates :title, presence: true
  validates :slug, uniqueness: { scope: :website_id }
  validates :slug, exclusion: { in: RESERVED_SLUGS, message: ->(*) { I18n.t("website.errors.reserved_slug") } },
                   unless: -> { home? || slug.blank? }
  validates :home, uniqueness: { scope: :website_id }, if: :home?

  scope :published, -> { where(published: true) }
  scope :in_nav, -> { where(nav_visible: true) }
end
