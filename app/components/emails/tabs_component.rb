# frozen_string_literal: true

module Emails
  class TabsComponent < ApplicationComponent
    attr_reader :tabs

    # @param tabs [Array<Hash>] Array of { label: String, path: String, active: Boolean }
    def initialize(tabs:)
      @tabs = tabs
    end

    def render?
      tabs.any?
    end
  end
end
