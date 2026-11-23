# frozen_string_literal: true

module Pages
  # Adds a run token (and, for the admin entry surface, the exact page) to a
  # destination path without disturbing its existing query.
  module RunLink
    def self.append(path, token, page: nil)
      uri = Addressable::URI.parse(path)
      values = uri.query_values || {}
      values["run"] = token if token.present?
      values["page"] = page.id.to_s if page
      uri.query_values = values if values.any?
      uri.to_s
    end
  end
end
