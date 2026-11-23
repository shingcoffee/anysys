# frozen_string_literal: true

module FlowchartDefinitions
  # Display label for a process action (or start/end) in the current locale.
  # Prefers template_labels, then the catalog nested flowchart_actions keys,
  # then the catalog's English title-case of the key.
  class ActionLabel
    def self.for(key)
      token = key.to_s
      template_key = "flowchart_elements.template_labels.#{token}"
      return I18n.t(template_key) if I18n.exists?(template_key, I18n.locale, fallback: false)

      i18n_key = "flowchart_actions.#{token}.label"
      return I18n.t(i18n_key) if I18n.exists?(i18n_key, I18n.locale, fallback: false)

      Palette.human_label(token)
    end
  end
end
