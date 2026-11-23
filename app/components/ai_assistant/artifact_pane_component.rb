# frozen_string_literal: true

module AiAssistant
  # Live preview rail for the record the assistant last applied.
  class ArtifactPaneComponent < ApplicationComponent
    # Virtual viewport the thumbnail iframe is laid out at before it is scaled
    # down to the rail width. Matches the preview layout's `max-w-4xl` content
    # column, so the miniature fills the frame and stays legible.
    FRAME_WIDTH = 960
    # Assumed page height until the framed document reports its real one on load.
    FRAME_HEIGHT = 1400
    # Pre-hydration scale: close to the rail width at the `lg` breakpoint so the
    # thumbnail does not flash full size before Stimulus measures the viewport.
    INITIAL_SCALE = 0.45

    attr_reader :conversation, :customer, :resolved

    def initialize(conversation:, customer:, viewer: nil)
      @conversation = conversation
      @customer = customer
      @viewer = viewer
      @resolved = conversation && AiAssistant::Assistant::Artifact.resolve(
        conversation,
        customer: customer,
        viewer: flowchart_viewer
      )
    end

    def pane_id
      AiAssistant::Stream::ARTIFACT_ID
    end

    def artifact_present?
      resolved.present?
    end

    def kind_label
      return nil unless resolved

      kind_label_for(resolved.kind)
    end

    def kind_label_for(kind)
      I18n.t("ai_assistant.assistant.artifact.kinds.#{kind}")
    end

    def kind_labels
      visible_kinds.map { |kind| kind_label_for(kind) }
    end

    def empty_body
      key =
        if flowchart_visible? && website_enabled? then "empty_with_flowchart_and_website"
        elsif flowchart_visible? then "empty_with_flowchart"
        elsif website_enabled? then "empty_with_website"
        else "empty"
        end
      I18n.t("ai_assistant.assistant.artifact.#{key}")
    end

    def open_url
      return nil unless resolved

      record = resolved.record
      cid = customer.id
      case resolved.kind
      when "website_page"
        helpers.edit_admin_modules_website_page_path(cid, record)
      when "page"
        helpers.admin_maintenance_page_path(cid, record)
      when "flowchart"
        helpers.admin_maintenance_flowchart_path(cid, record)
      else
        helpers.admin_maintenance_entity_path(cid, record)
      end
    end

    # Website pages are edited in the Website module, not Maintenance.
    def open_label
      if website_page?
        I18n.t("ai_assistant.assistant.artifact.open_editor")
      else
        I18n.t("ai_assistant.assistant.artifact.open_details")
      end
    end

    def preview_url(**options)
      case resolved&.kind
      when "page"
        helpers.admin_maintenance_page_preview_path(customer.id, resolved.record, **options)
      when "website_page"
        helpers.preview_admin_modules_website_page_path(customer.id, resolved.record, **options)
      end
    end

    # Same preview, without the standalone preview chrome, for framing inside
    # the thumbnail and the enlarge dialog.
    def frame_url
      preview_url(embed: 1)
    end

    def page_preview?
      preview_url.present?
    end

    # Idle header carries no subtitle — the empty state body explains the rail,
    # so repeating it here would only add noise.
    def subtitle
      return nil unless resolved
      return I18n.t("ai_assistant.assistant.artifact.current_saved") unless website_page?

      if resolved.record.published?
        I18n.t("ai_assistant.assistant.artifact.website_published")
      else
        I18n.t("ai_assistant.assistant.artifact.website_draft")
      end
    end

    # Draft website pages read amber and published ones green; every other
    # record is simply saved, so its dot stays neutral.
    def status_dot_class
      return "bg-border-strong" unless website_page?

      resolved.record.published? ? "bg-success" : "bg-warning"
    end

    def scroll_hint_id
      "ai-assistant-artifact-scroll-hint"
    end

    def no_visual_preview_body
      I18n.t("ai_assistant.assistant.artifact.no_visual_preview", kind: kind_label)
    end

    def canvas_style
      "width: #{FRAME_WIDTH}px; height: #{FRAME_HEIGHT}px; transform: scale(#{INITIAL_SCALE});"
    end

    # The canvas keeps its unscaled layout box, so the sheet carries the scaled
    # height that gives the rail its scroll extent.
    def sheet_height
      (FRAME_HEIGHT * INITIAL_SCALE).round
    end

    private

    def website_page?
      resolved&.kind == "website_page"
    end

    def visible_kinds
      AiAssistant::Assistant::Artifact::KINDS.reject do |kind|
        (kind == "flowchart" && !flowchart_visible?) || (kind == "website_page" && !website_enabled?)
      end
    end

    def website_enabled?
      return @website_enabled if defined?(@website_enabled)

      @website_enabled = AiAssistant::Assistant::Artifact.website_enabled?(customer)
    end

    def flowchart_visible?
      FlowchartVisibility.allowed?(flowchart_viewer)
    end

    def flowchart_viewer
      @viewer || conversation&.user
    end
  end
end
