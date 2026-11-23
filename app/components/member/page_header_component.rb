# frozen_string_literal: true

module Member
  # Top-of-page header: optional eyebrow / breadcrumb, title, subtitle,
  # optional right-aligned meta badge, optional action links.
  class PageHeaderComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(title:, subtitle: nil, eyebrow: nil, meta: nil, actions: [])
      @title    = title
      @subtitle = subtitle
      @eyebrow  = eyebrow
      @meta     = meta
      @actions  = Array(actions)
    end

    attr_reader :title, :subtitle, :eyebrow, :meta, :actions

    def variant_class(variant)
      case variant
      when :primary then chrome.primary_button_class
      when :danger  then chrome.danger_quiet_class
      else               chrome.secondary_button_class
      end
    end
  end
end
