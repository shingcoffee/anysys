# frozen_string_literal: true

class Website < ApplicationRecord
  include TenantScoped

  DEFAULT_THEME = Websites::Theme::DEFAULTS

  has_many :pages, -> { order(:position) },
           class_name: "WebsitePage",
           dependent: :destroy,
           inverse_of: :website

  validates :customer_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :skeleton_key, presence: true

  scope :published, -> { where(published: true) }

  def home_page
    pages.find_by(home: true)
  end
end
