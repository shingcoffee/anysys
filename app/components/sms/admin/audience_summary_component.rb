# frozen_string_literal: true

module Sms
  module Admin
    class AudienceSummaryComponent < BaseComponent
      def initialize(preview:)
        @preview = preview
      end
    end
  end
end
