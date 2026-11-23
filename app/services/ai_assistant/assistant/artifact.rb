# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Pins the dashboard preview to one tenant-owned record (entity, flowchart,
    # page, or website page) after an assistant apply. Lookups are always
    # scoped to the conversation customer — never another tenant, never a
    # shared row.
    class Artifact
      KINDS = %w[entity flowchart page website_page].freeze
      MODELS = {
        "entity" => Entity,
        "flowchart" => Flowchart,
        "page" => Page,
        "website_page" => WebsitePage
      }.freeze

      Resolved = Struct.new(:kind, :record, :label, keyword_init: true)

      def self.assign_record!(conversation, record:)
        kind = kind_for(record)
        unless record&.customer_id == conversation.customer_id
          raise ArgumentError, "artifact must belong to the conversation customer"
        end

        conversation.update!(artifact_kind: kind, artifact_id: record.id)
      end

      def self.clear!(conversation)
        conversation.update!(artifact_kind: nil, artifact_id: nil)
      end

      def self.resolve(conversation, customer:, viewer: nil)
        kind = conversation.artifact_kind.to_s
        return nil unless KINDS.include?(kind)
        return nil if kind == "flowchart" && !FlowchartVisibility.allowed?(viewer || conversation.user)
        return nil if kind == "website_page" && !website_enabled?(customer)

        id = conversation.artifact_id
        return nil if id.blank?

        record = MODELS.fetch(kind).where(customer_id: customer.id).find_by(id: id)
        return nil unless record

        Resolved.new(kind: kind, record: record, label: label_for(record))
      end

      def self.pick(website_page: nil, page: nil, flowchart: nil, entity: nil)
        website_page || page || flowchart || entity
      end

      def self.kind_for(record)
        return "website_page" if record.is_a?(WebsitePage)
        return "page" if record.is_a?(Page)
        return "flowchart" if record.is_a?(Flowchart)
        return "entity" if record.is_a?(Entity)

        raise ArgumentError, "unsupported artifact record"
      end

      def self.label_for(record)
        return record.display_label if record.respond_to?(:display_label) && record.display_label.present?
        return record.title if record.is_a?(WebsitePage)

        record.name
      end

      # A pinned website page outlives the module toggle; its preview and
      # editor routes 404 once the module is off, so the pane stops showing it.
      def self.website_enabled?(customer)
        FeatureModules::Website::Registration.enabled_for?(customer.id)
      end
    end
  end
end
