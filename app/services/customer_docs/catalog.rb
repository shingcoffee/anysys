# frozen_string_literal: true

# Ordered, allow-listed customer guides in doc/customer/{en,zh-CN}.
# Front matter supplies localized titles and summaries; each guide uses the
# required task-oriented sections and links only to other customer guide slugs.
# Owner-only flowchart and page builders are not part of this catalog.
module CustomerDocs
  module Catalog
    HOME_SLUG = "overview"
    LOCALES = %w[en zh-CN].freeze

    REQUIRED_HEADINGS = {
      "en" => ["Before you start", "Steps", "What to expect", "Troubleshooting", "Related guides"].freeze,
      "zh-CN" => ["开始前", "操作步骤", "预期结果", "常见问题", "相关指南"].freeze
    }.freeze

    # Contents groups follow MenuRegistry left-to-right. Maintenance is
    # owner-only. Modules has no dedicated customer guide; Payments, Email,
    # SMS, and Assistant sit under their own menu items instead.
    GROUPS = [
      { key: "home", pages: %w[overview getting-started].freeze }.freeze,
      { key: "assistant", pages: %w[assistant].freeze }.freeze,
      { key: "users", pages: %w[users].freeze }.freeze,
      { key: "payments", pages: %w[payments].freeze }.freeze,
      { key: "communication", pages: %w[email sms].freeze }.freeze,
      { key: "entities", pages: %w[records].freeze }.freeze,
      { key: "content", pages: %w[forms websites].freeze }.freeze,
      { key: "settings", pages: %w[settings billing support].freeze }.freeze
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
