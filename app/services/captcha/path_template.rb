# frozen_string_literal: true

module Captcha
  # Compiles stored URL templates (`/:customer_id/page/:uuid`) into a
  # single-segment matcher. Shared by the catalog and the throttle gate.
  module PathTemplate
    module_function

    def match?(template, path)
      compiled(template).match?(path.to_s)
    end

    def compiled(template)
      parts = template.to_s.split("/").map do |part|
        part.start_with?(":") ? "[^/]+" : Regexp.escape(part)
      end
      /\A#{parts.join("/")}\z/
    end
  end
end
