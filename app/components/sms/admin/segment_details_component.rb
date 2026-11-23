# frozen_string_literal: true

module Sms
  module Admin
    class SegmentDetailsComponent < BaseComponent
      def initialize(segment:, preview:)
        @segment, @preview = segment, preview
      end
    end
  end
end
