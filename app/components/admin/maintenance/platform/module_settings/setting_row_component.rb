# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class SettingRowComponent < ApplicationComponent
          def initialize(label:, description: nil, description_id: nil, state: nil, disabled_reason: nil)
            @label = label
            @description = description
            @description_id = description_id
            @state = state
            @disabled_reason = disabled_reason
          end

          attr_reader :label, :description, :description_id, :state, :disabled_reason

          # Merge these attributes into the slotted form control so assistive
          # technology can resolve the disabled explanation rendered by the row.
          def control_html_attributes
            described_by = []
            described_by << resolved_description_id if description.present?
            described_by << reason_id if disabled_reason.present?
            return {} if described_by.empty?

            { aria: { describedby: described_by.join(" ") } }
          end

          def resolved_description_id
            @resolved_description_id ||= description_id.presence || "module-settings-description-#{object_id}"
          end

          def reason_id
            @reason_id ||= "module-settings-disabled-reason-#{object_id}"
          end
        end
      end
    end
  end
end
