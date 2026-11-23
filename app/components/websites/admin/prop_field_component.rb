# frozen_string_literal: true

module Websites
  module Admin
    # One prop control in the site-page content editor.
    class PropFieldComponent < ApplicationComponent
      COUNTED_KEYS = %w[headline kicker heading subhead quote question title].freeze
      BODY_KEYS = %w[body answer bio address quote].freeze
      EMAIL_KEYS = %w[email].freeze
      PHONE_KEYS = %w[phone].freeze
      SEGMENTED_KEYS = (%w[tone image_side size aspect height placement] + Websites::SectionKit::STYLE_KEYS).freeze

      def initialize(field:, value:, field_id:, site_pages: [], option_label: nil, uploadable: false, workspace: false, label_key: nil, rows: nil, design: nil)
        @field = field
        @design = design
        @value = value.to_s
        @field_id = field_id
        @site_pages = Array(site_pages)
        @option_label = option_label
        @uploadable = uploadable
        @workspace = workspace
        @label_key = label_key
        @rows = rows
      end

      attr_reader :design

      def key
        @field[:key].to_s
      end

      def kind
        @field[:kind]
      end

      def options
        Array(@field[:options])
      end

      def hint
        @field[:hint]
      end

      def value
        @value
      end

      def field_id
        @field_id
      end

      def href?
        Websites::SectionKit::HREF_KEYS.include?(key)
      end

      def image?
        Websites::SectionKit::IMAGE_KEYS.include?(key)
      end

      def uploadable?
        @uploadable && image?
      end

      def workspace?
        @workspace
      end

      def counted?
        COUNTED_KEYS.include?(key)
      end

      def body?
        BODY_KEYS.include?(key) && kind == :textarea
      end

      def segmented?
        kind == :select && (SEGMENTED_KEYS.include?(key) || (workspace? && key == "span"))
      end

      def label
        t(@label_key || Websites::Admin::SectionEditorComponent::FIELD_LABEL_KEYS.fetch(key))
      end

      def email?
        EMAIL_KEYS.include?(key)
      end

      def phone?
        PHONE_KEYS.include?(key)
      end

      def input_type
        return "email" if email?
        return "tel" if phone?

        "text"
      end

      def input_action
        actions = [ "input->website-builder#markDirty" ]
        actions << "input->website-builder#countChars" if counted?
        actions.join(" ")
      end

      def site_pages
        @site_pages
      end

      def option_label_for(option)
        return option unless @option_label.respond_to?(:call)

        @option_label.call(option)
      end

      def textarea_rows
        return hint == :rich_text ? 8 : (@rows || (key == "subhead" ? 2 : 3)) if workspace?

        body? ? 8 : 3
      end

      def display_copy?
        !workspace? && %w[headline quote heading].include?(key)
      end

      def writing_input_class
        if workspace?
          [
            "input-field min-w-0",
            (kind == :textarea ? "min-h-9 resize-y leading-normal" : "h-9")
          ].compact.join(" ")
        elsif display_copy?
          "w-full border-0 bg-transparent px-0 py-1 text-[1.75rem] font-medium leading-tight tracking-tight text-text-primary shadow-none placeholder:text-text-muted focus:ring-0"
        elsif kind == :textarea
          "studio-field min-h-28 resize-y py-3 leading-relaxed"
        else
          "studio-field"
        end
      end

      def segmented_item_class
        return "flex h-8 items-center justify-center rounded-md px-3 text-sm font-medium text-text-tertiary transition-colors hover:text-text-primary peer-checked:bg-surface peer-checked:text-text-primary peer-checked:shadow-xs peer-checked:ring-1 peer-checked:ring-border-subtle peer-focus-visible:ring-2 peer-focus-visible:ring-accent pointer-coarse:h-10" if workspace?

        "flex h-10 flex-1 items-center justify-center px-3 text-sm font-medium text-text-secondary transition-colors hover:text-text-primary peer-checked:bg-surface peer-checked:font-semibold peer-checked:text-text-primary peer-checked:shadow-sm sm:flex-none"
      end
    end
  end
end
