# frozen_string_literal: true

module Admin
  module Settings
    class MemberVisibilityChoiceComponent < ApplicationComponent
      def initialize(choice:, name:)
        @choice, @name = choice, name
      end

      attr_reader :choice, :name
    end
  end
end
