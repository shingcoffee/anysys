# frozen_string_literal: true

module Sms
  module Admin
    class SectionComponent < ApplicationComponent
      attr_reader :title, :id

      def initialize(title:, id: nil)
        @title, @id = title, id
      end
    end
  end
end
