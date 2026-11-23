# frozen_string_literal: true

module PageBuilder
  class TemplateCardComponent < ApplicationComponent
    attr_reader :template

    def initialize(template:, selected: false, controller_name: "template-selector")
      @template = template
      @selected = selected
      @controller_name = controller_name
    end

    def selected?
      @selected
    end

    def controller_name
      @controller_name
    end

    def key
      template[:key]
    end

    def name
      template[:name]
    end

    def description
      template[:description]
    end

    def theme_preset
      template[:theme_preset]
    end

    def theme_preset_label
      t("comp_page_builder.theme_panel.preset.#{theme_preset}")
    end

    def theme_color
      preset = ThemeResolver::THEME_PRESETS[theme_preset]
      preset&.dig("primary_color") || "indigo"
    end

    def preview_rows
      template[:preview_rows] || []
    end

    def card_classes
      base = "group relative flex flex-col rounded-xl border-2 cursor-pointer transition-all hover:shadow-lg overflow-hidden"
      if selected?
        "#{base} border-indigo-500 ring-2 ring-indigo-500 shadow-md"
      else
        "#{base} border-gray-200 hover:border-indigo-300 bg-white"
      end
    end

    def accent_color_class
      case theme_color
      when "indigo"  then "bg-indigo-500"
      when "slate"   then "bg-slate-500"
      when "rose"    then "bg-rose-500"
      when "violet"  then "bg-violet-500"
      when "emerald" then "bg-emerald-500"
      else "bg-indigo-500"
      end
    end

    def accent_text_class
      case theme_color
      when "indigo"  then "text-indigo-600"
      when "slate"   then "text-slate-600"
      when "rose"    then "text-rose-600"
      when "violet"  then "text-violet-600"
      when "emerald" then "text-emerald-600"
      else "text-indigo-600"
      end
    end

    def theme_badge_classes
      case theme_color
      when "indigo"  then "bg-indigo-50 text-indigo-600 ring-indigo-200"
      when "slate"   then "bg-slate-50 text-slate-600 ring-slate-200"
      when "rose"    then "bg-rose-50 text-rose-600 ring-rose-200"
      when "violet"  then "bg-violet-50 text-violet-600 ring-violet-200"
      when "emerald" then "bg-emerald-50 text-emerald-600 ring-emerald-200"
      else "bg-gray-50 text-gray-600 ring-gray-200"
      end
    end

    def category_label
      PageLayoutTemplates.category_label(template[:category])
    end

    def category_group_label
      group = PageLayoutTemplates.category_groups.find { |g| g[:categories].include?(template[:category]) }
      group ? PageLayoutTemplates.category_group_label(group) : ""
    end

    # Width CSS classes for preview elements
    def width_class(width)
      case width
      when "half"  then "w-[calc(50%-2px)]"
      when "third" then "w-[calc(33.33%-2px)]"
      else "w-full"
      end
    end
  end
end
