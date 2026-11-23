# frozen_string_literal: true

# SectionNavComponent
#
# The canonical underline tab strip for an admin area whose sections are
# separate pages (platform billing, platform module settings, …). Every tab is
# a link to a real path — this component never manages client-side tab state,
# which is what keeps a section bookmarkable and back-button friendly.
#
#   render SectionNavComponent.new(
#     label: t("..."),
#     tabs: [{ id: :overview, label: "Overview", path: "/…", active: true }]
#   )
#
# `id` is optional and, when given, is emitted as `data-section-nav-tab` so
# feature specs can target a tab without matching on translated text. An
# optional `count` renders as a small badge after the label.
class SectionNavComponent < ApplicationComponent
  def initialize(label:, tabs:, **html_attributes)
    @label = label
    @tabs = Array(tabs).compact
    @html_attributes = html_attributes
  end

  attr_reader :label, :tabs

  def render?
    tabs.size > 1
  end

  def html_attributes
    merge_html_attributes(
      { class: "mb-6", aria: { label: label } },
      @html_attributes
    )
  end

  def tab_classes(tab)
    base = "inline-flex items-center gap-2 whitespace-nowrap border-b-2 px-3 py-2.5 text-body-sm font-medium transition-colors"
    state = if tab[:active]
      "border-accent text-accent"
    else
      "border-transparent text-text-secondary hover:border-border hover:text-text-primary"
    end

    "#{base} #{state}"
  end

  def count_classes(tab)
    state = tab[:active] ? "bg-accent-subtle text-accent" : "bg-surface-active text-text-tertiary"
    "inline-flex min-w-5 items-center justify-center rounded-md px-1.5 text-[11px] font-medium leading-5 tabular-nums #{state}"
  end
end
