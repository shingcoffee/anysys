# frozen_string_literal: true

class TierBadgeComponent < ApplicationComponent
  TIER_STYLES = {
    basic: "bg-gray-100 text-gray-800",
    standard: "bg-blue-100 text-blue-800",
    premium: "bg-purple-100 text-purple-800",
    enterprise: "bg-amber-100 text-amber-800"
  }.freeze

  BASE_CLASSES = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize"

  attr_reader :tier

  def initialize(tier:)
    @tier = tier.to_sym
  end

  def tier_classes
    "#{BASE_CLASSES} #{TIER_STYLES.fetch(tier, TIER_STYLES[:basic])}"
  end

  def tier_label
    t("chrome.customer_form.tiers.#{tier}")
  end
end
