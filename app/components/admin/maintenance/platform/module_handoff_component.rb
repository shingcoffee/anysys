# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # "Integration Contract" body of the Handoff card on the platform Module
      # Settings Developer pane.
      #
      # Surfaces, per module, the handoff surface a Page uses when it hands
      # control to the module: the entry path, the default exit target, the
      # INPUT fields a page must map form data into (the source of the
      # "field mapping" the page builder asks for), and the OUTPUT fields the
      # module returns on completion. Modules that declare no contract render a
      # clear empty state rather than being hidden.
      class ModuleHandoffComponent < ApplicationComponent
        def initialize(feature_module:)
          @feature_module = feature_module
        end

        private

        attr_reader :feature_module

        def registration
          @registration ||= feature_module.registration_class
        end

        def input_fields  = registration.input_contract_fields
        def output_fields = registration.output_contract_fields

        def contract_groups
          [
            { key: :input, fields: input_fields,
              title: I18n.t("comp_admin.module_handoff.input_fields"),
              note: I18n.t("comp_admin.module_handoff.input_fields_note"),
              empty: I18n.t("comp_admin.module_handoff.no_inputs") },
            { key: :output, fields: output_fields,
              title: I18n.t("comp_admin.module_handoff.output_fields"),
              note: I18n.t("comp_admin.module_handoff.output_fields_note"),
              empty: I18n.t("comp_admin.module_handoff.no_output") }
          ]
        end

        # entry_path blocks build a URL from a customer; on the platform page we
        # illustrate with the current (platform-owner) customer. Guard against a
        # missing Current.customer so the card never blows up the show page.
        def entry_path
          return nil unless Current.customer

          registration.entry_path_for(Current.customer)
        rescue StandardError
          nil
        end

        def default_exit_summary
          config = registration.default_exit_config
          return nil if config.blank?

          config = config.symbolize_keys
          case config[:kind].to_s
          when "route"     then I18n.t("comp_admin.module_handoff.exit.route", name: config[:name])
          when "page"      then I18n.t("comp_admin.module_handoff.exit.page", page_id: config[:page_id])
          when "flowchart" then I18n.t("comp_admin.module_handoff.exit.flowchart", flowchart_uuid: config[:flowchart_uuid])
          when "url"       then I18n.t("comp_admin.module_handoff.exit.url", url: config[:url])
          else config[:kind].presence || I18n.t("common.labels.em_dash")
          end
        end
      end
    end
  end
end
