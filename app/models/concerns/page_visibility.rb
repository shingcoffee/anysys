# frozen_string_literal: true

# PageVisibility
#
# Exact audience-set predicates for the Page model. A page is visible to an
# audience only when that audience is in the set; unknown audiences are false.
#
# Usage:
#   page.visible_to?(:member)   # => true when audience_member is set
#   page.visible_audiences      # => ["member", "public"]
#   Page.for_audience("public")
#
module PageVisibility
  extend ActiveSupport::Concern

  AUDIENCES = %w[admin member public].freeze
  ACTION_KEY = /\A[a-z][a-z0-9_]{1,62}\z/

  included do
    scope :for_audience, ->(audience) {
      column = { "admin" => :audience_admin, "member" => :audience_member, "public" => :audience_public }[audience.to_s]
      column ? where(column => true) : none
    }

    before_validation :normalize_action_key
    validate :audiences_must_be_present
    validate :action_key_must_be_valid
  end

  def visible_to?(audience)
    key = audience.to_s
    return false unless AUDIENCES.include?(key)

    public_send("audience_#{key}")
  end

  def visible_audiences
    AUDIENCES.select { |audience| public_send("audience_#{audience}") }
  end

  def visible_audiences=(list)
    selected = Array(list).map(&:to_s)
    AUDIENCES.each { |audience| public_send("audience_#{audience}=", selected.include?(audience)) }
  end

  private

  def normalize_action_key
    self.action_key = nil if action_key.blank?
  end

  def audiences_must_be_present
    return if visible_audiences.any?

    errors.add(:base, I18n.t("maint_core.errors.validations.page_audiences_blank"))
  end

  def action_key_must_be_valid
    return if action_key.blank?
    return if action_key.match?(ACTION_KEY)

    errors.add(:action_key, I18n.t("maint_core.errors.validations.page_action_key_invalid"))
  end
end
