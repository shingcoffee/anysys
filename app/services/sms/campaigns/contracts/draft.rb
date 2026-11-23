# frozen_string_literal: true

require "reform/form"

module Sms
  module Campaigns
    module Contracts
      class Draft < Reform::Form
        FIELDS = %i[name template_id segment_id variable_map send_timing scheduled_at timezone
                    quiet_hours_start quiet_hours_end frequency_window_hours send_rate_per_minute deadline_hours].freeze
        FIELDS.each { |field| property field }
        attr_accessor :customer
        attr_reader :template, :segment

        validate :bounded_fields
        validate :selected_references
        validate :safe_mapping

        def complete_blockers
          blockers = []
          blockers << :template_required unless template
          blockers << :mapping_incomplete if template && !VariableMap.valid?(map: variable_map,
            required_vars: template.required_vars, customer: customer, complete: true)
          blockers << :schedule_required if send_timing == "scheduled" && scheduled_at.nil?
          blockers
        end

        private

        def bounded_fields
          invalid(:name) unless name.is_a?(String) && name.valid_encoding? && (name.encoding == Encoding::UTF_8 || name.ascii_only?) &&
            name.present? && name.bytesize <= 200
          invalid(:send_timing) unless %w[immediate scheduled].include?(send_timing)
          invalid(:timezone) unless Schedule.valid_zone?(timezone)
          { quiet_hours_start: 0..23, quiet_hours_end: 0..23, frequency_window_hours: 1..168,
            send_rate_per_minute: 1..60, deadline_hours: 1..168 }.each do |field, range|
            value = public_send(field)
            invalid(field) unless value.is_a?(Integer) && range.cover?(value)
          end
          invalid(:quiet_hours_end) if quiet_hours_start == quiet_hours_end
          invalid(:scheduled_at) unless scheduled_at.nil? || scheduled_at.is_a?(Time) || scheduled_at.is_a?(ActiveSupport::TimeWithZone)
        end

        def selected_references
          @template = nil
          @segment = nil
          if template_id
            @template = Sms::Template.active.find_by(id: template_id) if template_id.is_a?(Integer) && template_id.positive?
            invalid(:template_id) unless template && template.purpose == "marketing" &&
              VariableMap.valid_body?(template.body_template, template.required_vars)
          end
          if segment_id
            @segment = Sms::Audience::Segment.find_by(customer_id: customer.id, id: segment_id) if segment_id.is_a?(Integer) && segment_id.positive?
            invalid(:segment_id) unless segment && Sms::Audience::SegmentQuery.valid?(customer: customer, rules: segment.segment_rules)
          end
        end

        def safe_mapping
          invalid(:variable_map) unless VariableMap.valid?(map: variable_map, required_vars: template&.required_vars,
                                                         customer: customer)
        end

        def invalid(field)
          errors.add(field, I18n.t("sms_campaigns.errors.invalid_field"))
        end
      end
    end
  end
end
