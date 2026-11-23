# frozen_string_literal: true

module Sms
  module Admin
    class SegmentFormComponent < BaseComponent
      attr_reader :segment, :catalog

      def initialize(segment:, catalog:, form_values:, preview:, errors:)
        @segment, @catalog, @form_values, @preview, @errors = segment, catalog, form_values || {}, preview, errors || {}
      end

      def save_path
        segment.persisted? ? sms_path(:segment, segment) : sms_path(:segments)
      end

      def preview_path
        segment.persisted? ? sms_path(:preview_segment, segment) : sms_path(:preview_segments)
      end

      def rules_invalid?
        %i[segment_rules segment_rules_json].any? { |key| @errors[key].present? }
      end
    end
  end
end
