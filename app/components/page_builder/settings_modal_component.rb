# frozen_string_literal: true

module PageBuilder
  # The page-builder "Page Settings" modal.
  #
  # A sidebar-navigated, sectioned layout: the visitor picks a concern
  # (General / Inputs / Multi-step / After submit) on the left and edits only
  # that pane on the right.
  #
  # It is a pure presentation shell over the live page-builder Stimulus state:
  # every control keeps its original `data-property` / `data-action` so the
  # builder serializes `configuration` exactly as before — this component only
  # reorganizes the markup. Section switching is handled by the small
  # `page-settings` Stimulus controller; the modal open/close wiring stays with
  # the shared ConfigModalComponent shell.
  class SettingsModalComponent < ApplicationComponent
    INPUT_CLASS = "w-full px-3 py-2 text-sm border border-gray-300 rounded-lg " \
                  "focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 bg-white"
    LABEL_CLASS = "block text-sm font-medium text-gray-700 mb-1"

    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end

    private

    attr_reader :page, :customer_id

    def form_settings
      @form_settings ||= (page.configuration_json&.dig("form_settings") || {})
    end

    def wizard_settings
      @wizard_settings ||= (page.configuration_json&.dig("wizard_settings") || {})
    end

    def submit_button_text = form_settings["submit_button_text"].presence || t("common.actions.submit")
    def wizard_mode?       = wizard_settings["wizard_mode"].to_s == "true"
    def show_progress?     = wizard_settings["show_progress"] != false
    def success_message    = form_settings["success_message"]
    def submission_modes   = page.submission_modes
    def manages_rows?      = page.manages_rows?

    # Fields of the page's entity that hold another record, and so can be
    # filled from an earlier step.
    def reference_fields
      locked = page.input_slugs
      Array(page.entity&.property_schema_json).grep(Hash).filter_map do |attribute|
        entity_id = Entities::BridgeParticipants.referenced_entity_id(attribute)
        next if entity_id.blank?

        { slug: attribute["name_slug"], label: attribute["name"], entity_id: entity_id,
          locked: locked.include?(attribute["name_slug"]) }
      end
    end

    def sections
      [
        { key: "general",      label: section_text("general.label"),      hint: section_text("general.hint"),      icon: :submit },
        { key: "inputs",       label: section_text("inputs.label"),       hint: section_text("inputs.hint"),       icon: :lock },
        { key: "steps",        label: section_text("steps.label"),        hint: section_text("steps.hint"),        icon: :steps },
        { key: "after_submit", label: section_text("after_submit.label"), hint: section_text("after_submit.hint"), icon: :flag }
      ]
    end

    def section_text(key)
      I18n.t("comp_page_builder.settings_modal.sections.#{key}")
    end

    ICONS = {
      submit: "M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5",
      steps:  "M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25a2.25 2.25 0 0 1-2.25-2.25v-2.25Z",
      lock:   "M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z",
      flag:   "M3 3v1.5M3 21v-6m0 0 2.77-.693a9 9 0 0 1 6.208.682l.108.054a9 9 0 0 0 6.086.71l3.114-.732a48.524 48.524 0 0 1-.005-10.499l-3.11.732a9 9 0 0 1-6.085-.711l-.108-.054a9 9 0 0 0-6.208-.682L3 4.5M3 15V4.5",
      shield: "M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z"
    }.freeze

    def icon_path(key) = ICONS[key]
  end
end
