# frozen_string_literal: true

module Websites
  module Admin
    # Public address line under the page editor title. Links out only when
    # visitors can open it (site and page both published).
    class PageAddressComponent < ApplicationComponent
      def initialize(path:, live: false)
        @path = path.to_s
        @live = live
      end

      attr_reader :path

      def live?
        @live
      end

      def render?
        path.present?
      end
    end
  end
end
