# frozen_string_literal: true

module Websites
  module Admin
    # Label row shared by every editor element: the label on the left, then an
    # optional aside (character count, add button) and the element's Design
    # trigger pinned to the right edge, so triggers line up down the inspector.
    # The trigger fades in on its nearest `group/design` ancestor, which the
    # caller must provide.
    class FieldHeaderComponent < ApplicationComponent
      renders_one :aside

      attr_reader :design

      def initialize(design: nil)
        @design = design
      end
    end
  end
end
