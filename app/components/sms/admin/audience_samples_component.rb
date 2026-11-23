# frozen_string_literal: true

module Sms
  module Admin
    class AudienceSamplesComponent < BaseComponent
      def initialize(preview:)
        @preview = preview
      end
    end
  end
end
