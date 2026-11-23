# frozen_string_literal: true

module Sms
  module Admin
    class ConsentFormComponent < BaseComponent
      attr_reader :contact

      def initialize(contact:, form_values:, errors:)
        @contact, @form_values, @errors = contact, form_values || {}, errors || {}
      end
    end
  end
end
