# frozen_string_literal: true

module Member
  # Descriptor + per-tenant overlay merged into a single object that exposes
  # the same surface interface (label, icon, index, detail) the kit
  # components and the controller already consume. The scope lambda is
  # security-critical and never overridable — it always comes from the
  # descriptor.
  class EffectiveSurface
    def initialize(descriptor:, settings:, source_key: nil)
      @descriptor = descriptor
      @settings   = settings
      @source_key = source_key&.to_sym
    end

    def key        ; @descriptor.key                               ; end
    def source_key ; @source_key                                   ; end
    def label    ; @settings.label_or(@descriptor.label)         ; end
    def icon     ; @settings.icon_or(@descriptor.icon)           ; end
    def position ; @settings.position_or(@descriptor.default_position_or_default) ; end
    def enabled? ; @settings.enabled_or(@descriptor.default_enabled?) ; end

    def enabled_for?(user)
      enabled? && @descriptor.enabled_for?(user)
    end

    def row_action
      @settings.row_action_or(I18n.t("member.entity_surfaces.row_action_default"))
    end

    def index
      @effective_index ||= EffectiveIndex.new(
        descriptor: @descriptor.index, settings: @settings,
        descriptor_default_subtitle: @descriptor.index.subtitle
      )
    end

    def detail
      @effective_detail ||= EffectiveDetail.new(descriptor: @descriptor.detail, settings: @settings)
    end

    attr_reader :descriptor, :settings

    # Wrapper exposing the same shape as Member::Surface::Index, with
    # overlay logic applied for visibility-narrowing fields. Scope, columns
    # signature, and per-column callables are NEVER altered.
    class EffectiveIndex
      def initialize(descriptor:, settings:, descriptor_default_subtitle:)
        @descriptor = descriptor
        @settings   = settings
        @default_subtitle = descriptor_default_subtitle
      end

      def title       ; @descriptor.title                                          ; end
      def subtitle    ; @settings.subtitle_or(@default_subtitle)                   ; end
      def scope       ; @descriptor.scope                                          ; end
      def per_page    ; @settings.per_page_or(@descriptor.per_page_or_default)     ; end
      def per_page_or_default ; per_page ; end

      def empty_state
        original = @descriptor.empty_state || {}
        original.merge(
          headline: @settings.empty_headline_or(original[:headline]),
          body:     @settings.empty_body_or(original[:body])
        )
      end

      def columns
        visible = @settings.visible_column_keys
        @descriptor.columns.select { |c|
          c[:hideable] == false || visible.nil? || visible.include?(c[:key])
        }
      end
    end

    # Wrapper exposing the same shape as Member::Surface::Detail.
    class EffectiveDetail
      def initialize(descriptor:, settings:)
        @descriptor = descriptor
        @settings   = settings
      end

      def title    ; @descriptor.title    ; end
      def subtitle ; @descriptor.subtitle ; end
      def meta     ; @descriptor.meta     ; end

      def sections
        visible_section_keys = @settings.visible_section_keys
        visible_row_keys     = @settings.visible_detail_row_keys

        @descriptor.sections
          .select { |s|
            s[:hideable] == false || visible_section_keys.nil? || visible_section_keys.include?(s[:key])
          }
          .map { |s| narrow_rows(s, visible_row_keys) }
      end

      private

      def narrow_rows(section, visible_row_keys)
        return section unless section[:rows].is_a?(Array)
        return section if visible_row_keys.nil?

        narrowed = section[:rows].select { |r|
          r[:hideable] == false || visible_row_keys.include?(r[:key])
        }
        section.merge(rows: narrowed)
      end
    end
  end
end
