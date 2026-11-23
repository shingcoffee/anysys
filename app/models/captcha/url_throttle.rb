# frozen_string_literal: true

module Captcha
  class UrlThrottle < ApplicationRecord
    self.table_name = "captcha_url_throttles"

    MATCH_KINDS = %w[template exact].freeze

    belongs_to :customer, optional: true
    belongs_to :page, optional: true
  end
end
