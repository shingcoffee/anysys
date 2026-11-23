# frozen_string_literal: true

module Captcha
  class ReturnTo
    def self.safe?(value, request: nil)
      path = value.to_s
      return false if path.blank?
      return false unless path.start_with?("/")
      return false if path.start_with?("//")
      return false if path.include?("://")

      uri = URI.parse(path)
      return false if uri.host.present?
      return false if uri.path.blank?

      Captcha::UrlMatcher.for_path(uri.path, request: request).present?
    rescue URI::InvalidURIError
      false
    end

    def self.path_and_query(value, request: nil)
      return nil unless safe?(value, request: request)

      uri = URI.parse(value.to_s)
      uri.query.present? ? "#{uri.path}?#{uri.query}" : uri.path
    end
  end
end
