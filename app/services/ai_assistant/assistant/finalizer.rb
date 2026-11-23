# frozen_string_literal: true

module AiAssistant
  module Assistant
    class Finalizer
      Result = Struct.new(
        :body,
        :status,
        :metadata,
        :artifact,
        :artifact_kind,
        keyword_init: true
      )

      def self.call(turn:, conversation:, write_guard: nil)
        new(
          turn: turn,
          conversation: conversation,
          write_guard: write_guard
        ).call
      end

      def initialize(turn:, conversation:, write_guard:)
        @turn = turn
        @conversation = conversation
        @write_guard = write_guard
      end

      def call
        page_results = @turn.status == "complete" ? generate_pages : []
        artifact = selected_record(page_results)
        body = joined_body(page_results)
        body = append_verification(body, artifact) if artifact

        Result.new(
          body: body,
          status: @turn.status,
          metadata: changes_metadata(page_results),
          artifact: artifact,
          artifact_kind: artifact && Artifact.kind_for(artifact)
        )
      end

      private

      def customer
        @conversation.customer
      end

      def generate_pages
        return [] unless @turn.entity_result&.applied

        names_for(@turn.entity_result, :created, :updated).filter_map do |name|
          entity = lookup_named(Entity, [name])
          next unless entity

          generate_page(entity)
        end
      end

      def generate_page(entity)
        operation = -> { GeneratePage.call(entity: entity, customer: customer) }
        return operation.call unless @write_guard

        @write_guard.call(&operation)
      end

      def joined_body(page_results)
        Markdown.compose(@turn.body, page_results.filter_map { |result| result.message.presence })
      end

      # The admin form of each page this turn generated or reused, except the
      # form of an entity another of these pages' entities associates with:
      # the primary entity's form already collects those association rows.
      def page_links(page_results)
        pages = turn_pages(page_results)
        targeted = pages.flat_map { |page| associated_entity_ids(page) - [page.entity_id.to_s] }
        primary = pages.reject { |page| targeted.include?(page.entity_id.to_s) }
        (primary.presence || pages)
          .select { |page| page.launched? && page.visible_to?(:admin) }
          .map { |page| { "id" => page.id, "name" => page.name } }
      end

      def turn_pages(page_results)
        effect_pages = Array(@turn.effects).filter_map do |effect|
          record = effect[:record] || effect["record"]
          record if record.is_a?(Page) && record.customer_id == @conversation.customer_id
        end
        (page_results.filter_map(&:page) + effect_pages).uniq(&:id)
      end

      def associated_entity_ids(page)
        Array(page.entity&.associations_list).map { |association| association["target_entity_id"].to_s }
      end

      def selected_record(page_results)
        page = page_results.filter_map(&:page).last
        entity = lookup_named(Entity, names_for(@turn.entity_result, :created, :updated))
        flowchart = lookup_named(
          Flowchart,
          names_for(@turn.flowchart_result, :created, :updated)
        )
        effect_record = Array(@turn.effects).filter_map { |effect| effect[:record] || effect["record"] }.last
        Artifact.pick(
          website_page: website_page,
          page: page || (effect_record if effect_record.is_a?(Page)),
          flowchart: flowchart,
          entity: entity
        )
      end

      # The pane shows one page: the first that shows the site's own photos,
      # so photos the admin just attached are on screen rather than hidden
      # behind a later text-only page (contact, adopt); otherwise the last.
      def website_page
        result = @turn.website_result
        return unless result&.applied

        pages = Array(result.pages)
        pages.find { |page| shows_site_media?(page) } || pages.last
      end

      def shows_site_media?(page)
        Websites::Assistant::SchemaValidator.image_values(page.sections).any? { |url| Websites::Href::MEDIA_PATH.match?(url) }
      end

      def append_verification(body, artifact)
        verification = Verify.call(
          kind: Artifact.kind_for(artifact),
          record: artifact,
          customer: customer
        )
        return body if verification.ok?

        Markdown.compose(
          body,
          [I18n.t("ai_assistant.assistant.verify.failed", issues: verification.issues.join(" "))]
        )
      end

      def lookup_named(model, names)
        name = Array(names).map(&:to_s).reject(&:blank?).last
        return if name.blank?

        model.where(customer_id: @conversation.customer_id, name: name).first
      end

      def names_for(result, *keys)
        return [] unless result

        keys.flat_map do |key|
          result.respond_to?(key) ? Array(result.public_send(key)) : []
        end
      end

      def changes_metadata(page_results)
        changes = []
        append_changes(changes, "entity", @turn.entity_result)
        append_changes(changes, "flowchart", @turn.flowchart_result)
        append_changes(changes, "website_page", @turn.website_result)
        page_results.each do |result|
          next unless result&.created.present? && result.ok

          changes << { "kind" => "page", "action" => "created", "name" => result.created }
        end
        Array(@turn.effects).each do |effect|
          kind = effect[:kind] || effect["kind"]
          action = effect[:action] || effect["action"]
          record = effect[:record] || effect["record"]
          next if kind.blank? || action.blank? || record.blank? || record.is_a?(AiAssistant::SubsystemBuild)

          changes << { "kind" => kind.to_s, "action" => action.to_s, "name" => record.name }
        end
        metadata = { "changes" => changes }
        build = subsystem_build
        metadata["subsystem_build"] = { "id" => build.id } if build
        links = page_links(page_results)
        metadata["page_links"] = links if links.any?
        website_undo = @turn.website_result&.applied ? Array(@turn.website_result.undo) : []
        metadata[Websites::Assistant::Undo::KEY] = { "pages" => website_undo } if website_undo.any?
        if @turn.pending_confirmation.present?
          metadata["pending_confirmation"] = @turn.pending_confirmation
        end
        if @turn.status == "complete"
          questions = Array(@turn.questions)
          assumptions = Array(@turn.assumptions)
          metadata["questions"] = questions if questions.any?
          metadata["assumptions"] = assumptions if assumptions.any?
        end
        metadata
      end

      def subsystem_build
        Array(@turn.effects).filter_map { |effect| effect[:record] || effect["record"] }
                            .grep(AiAssistant::SubsystemBuild).last
      end

      def append_changes(changes, kind, result)
        return unless result

        Array(result.try(:created)).each do |name|
          changes << { "kind" => kind, "action" => "created", "name" => name }
        end
        Array(result.try(:updated)).each do |name|
          changes << { "kind" => kind, "action" => "updated", "name" => name }
        end
      end
    end
  end
end
