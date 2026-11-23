# frozen_string_literal: true

module Admin
  module Settings
    # Adapts an EffectiveSurface (descriptor + tenant overlay) into the form
    # field values the admin settings card needs. Pure value object.
    class MemberRowPresenter
      KNOWN_UNTITLED_SECTIONS = %w[primary].freeze

      def initialize(effective:)
        @effective = effective
      end

      attr_reader :effective

      def surface_key  ; effective.key.to_s ; end
      def descriptor   ; effective.descriptor ; end
      def settings     ; effective.settings   ; end

      def enabled?     ; effective.enabled?   ; end
      def label        ; settings.label_or(default_label) ; end
      def icon         ; settings.icon_or(descriptor.icon).to_s ; end
      def subtitle     ; settings.subtitle_or(relationship_page? ? I18n.t("settings_people.relationship_description", name: default_label) : descriptor.index.subtitle).to_s ; end
      def position     ; settings.position_or(descriptor.default_position_or_default) ; end
      def per_page     ; settings.per_page_or(descriptor.index.per_page_or_default) ; end

      def empty_headline
        default = if relationship_page?
          I18n.t("member.entity_surfaces.empty_headline", name: default_label.downcase)
        else
          descriptor.index.empty_state.to_h[:headline]
        end
        settings.empty_headline_or(default).to_s
      end

      def empty_body
        settings.empty_body_or(descriptor.index.empty_state.to_h[:body]).to_s
      end

      def column_choices
        descriptor.index.columns.map { |c|
          {
            key:     c[:key],
            label:   c[:label],
            locked:  c[:hideable] == false,
            checked: c[:hideable] == false || (settings.visible_column_keys || all_column_keys).include?(c[:key])
          }
        }
      end

      def detail_row_choices
        descriptor.detail.sections.flat_map { |section|
          Array(section[:rows]).map { |row|
            {
              key:           row[:key],
              section_key:   section[:key],
              label:         row[:label],
              section_label: section[:title].to_s,
              locked:        row[:hideable] == false,
              checked:       row[:hideable] == false || (settings.visible_detail_row_keys || all_row_keys).include?(row[:key])
            }
          }
        }
      end

      def section_choices
        descriptor.detail.sections.map { |section|
          {
            key:     section[:key],
            label:   section_choice_label(section),
            locked:  section[:hideable] == false,
            checked: section[:hideable] == false || (settings.visible_section_keys || all_section_keys).include?(section[:key])
          }
        }
      end

      private

      # Generated relationship pages carry their participant display names in
      # the descriptor. Use those names without parsing internal association slugs.
      def default_label
        return descriptor.label unless relationship_page?

        fields = Array(descriptor.groups).flat_map { |group| Array(group[:attributes]) }
        participants = fields.select { |field| field["type"] == "EntityReference" }.first(2)
        names = participants.map { |field| field["display_label"].presence || field["name"].presence }
        return I18n.t("settings_people.details_fallback") unless names.size == 2 && names.all?(&:present?)

        I18n.t("settings_people.relationship_name", source: names.first, target: names.last)
      end

      def relationship_page?
        effective.source_key.to_s == "entities" && descriptor.label.to_s.start_with?("assoc_") &&
          surface_key.start_with?("entity_")
      end

      def section_choice_label(section)
        return section[:title] if section[:title].present?

        key = section[:key].to_s
        if KNOWN_UNTITLED_SECTIONS.include?(key)
          I18n.t("comp_admin.member_surface_form.section_keys.#{key}")
        else
          I18n.t("settings_people.details_fallback")
        end
      end

      def all_column_keys  ; descriptor.index.columns.map { |c| c[:key] } ; end
      def all_row_keys     ; descriptor.detail.sections.flat_map { |s| Array(s[:rows]).map { |r| r[:key] } } ; end
      def all_section_keys ; descriptor.detail.sections.map { |s| s[:key] } ; end
    end
  end
end
