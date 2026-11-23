# frozen_string_literal: true

# Ordered map of the in-app developer reference.
#
# Each slug is a page in both doc/reference/en and doc/reference/zh-CN.
# A page has YAML front matter (title, summary) and these sections:
#
#   en:    Summary, Flow, Implementation, Where to pay attention, Key code
#   zh-CN: 概要, 流程, 实现, 需要特别注意, 关键代码
#
# Callouts use a fenced block the renderer understands:
#
#   :::attention
#   ...
#   :::
#
# Cross-links are bare slugs, for example [Entity builder](entity-builder).
module DeveloperDocs
  module Catalog
    HOME_SLUG = "overview"
    LOCALES = %w[en zh-CN].freeze

    REQUIRED_HEADINGS = {
      "en" => ["Summary", "Flow", "Implementation", "Where to pay attention", "Key code"].freeze,
      "zh-CN" => ["概要", "流程", "实现", "需要特别注意", "关键代码"].freeze
    }.freeze

    GROUPS = [
      { key: "orientation", pages: %w[overview system-map dashboard].freeze },
      { key: "access", pages: %w[tenancy-and-roles authentication oauth access-grants person-linking audience-flows].freeze },
      { key: "builders", pages: %w[entity-builder flowchart-builder flowchart-step-actions page-builder website-builder code-generators].freeze },
      { key: "runtime", pages: %w[shared-resources constants flowchart-runtime page-rendering page-shortcuts module-framework operations-api].freeze },
      { key: "modules", pages: %w[authentication-module payments email sms sms-campaigns captcha ai-assistant speech-to-text websites billing].freeze },
      { key: "operations", pages: %w[customers custom-domains announcements support-tickets customer-documentation industry-templates background-jobs docker-image internationalization member-and-public].freeze }
    ].freeze

    def self.groups = GROUPS

    def self.slugs
      @slugs ||= GROUPS.flat_map { |group| group[:pages] }.freeze
    end

    def self.slug?(value)
      slugs.include?(value.to_s)
    end
  end
end
