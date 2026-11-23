# frozen_string_literal: true

module Admin
  module Settings
    # One preference inside a settings card: label and explanation on the left,
    # the control on the right. Matches the platform module-settings rows.
    class SettingRowComponent < ApplicationComponent
      attr_reader :label, :description, :description_id, :label_for, :state, :required

      def initialize(label:, description: nil, description_id: nil, label_for: nil, state: nil, required: false)
        @label = label
        @description = description
        @description_id = description_id
        @label_for = label_for
        @state = state
        @required = required
      end
    end
  end
end
