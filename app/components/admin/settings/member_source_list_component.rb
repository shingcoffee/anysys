# frozen_string_literal: true

module Admin
  module Settings
    class MemberSourceListComponent < ApplicationComponent
      def initialize(rows:, source:, customer:)
        @rows, @source, @customer = rows, source, customer
      end

      attr_reader :rows, :source, :customer
    end
  end
end
