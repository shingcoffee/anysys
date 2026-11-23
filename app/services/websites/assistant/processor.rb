# frozen_string_literal: true

module Websites
  module Assistant
    # One `apply_website` completion → assistant message body.
    #
    # The document is validated against the section kit, the tenant's site and
    # the conversation's uploads. Contract slips go back to the model through
    # AiAssistant::Assistant::DocumentRepair; so do attached images the
    # document leaves out, but only once — after that nudge the document is
    # applied and the reply names the images left unplaced. A valid document is
    # written as drafts in one transaction under the generation write guard.
    class Processor
      MAX_REPAIR = 2

      Message = Struct.new(:body, :status, :intent, :applied, :created, :updated, :pages, :undo, keyword_init: true)

      Outcome = Struct.new(:created, :updated, :pages, :undo, :errors, keyword_init: true) do
        def ok? = errors.empty?
      end
      private_constant :Outcome

      def self.call(text:, customer:, conversation:, chat: nil, write_guard: nil)
        new(text: text, customer: customer, conversation: conversation, chat: chat, write_guard: write_guard).call
      end

      def initialize(text:, customer:, conversation:, chat:, write_guard:)
        @text = text
        @customer = customer
        @conversation = conversation
        @chat = chat
        @write_guard = write_guard
      end

      def call
        return message(t("module_disabled"), intent: Extraction::INTENT) unless module_enabled?

        extraction = Extraction.parse(@text)
        return message(I18n.t("ai_assistant.assistant.extraction_invalid"), status: "failed") unless extraction.valid?

        @website = resolve_website
        return message(t("provision_failed"), intent: extraction.intent) unless @website

        persist_with_repair(extraction)
      end

      private

      def module_enabled?
        FeatureModules::Website::Registration.enabled_for?(@customer.id)
      end

      def resolve_website
        Website.find_by(customer_id: @customer.id) || provisioned_website
      end

      def provisioned_website
        result = guarded { Websites::Activities::Provision.call(customer: @customer) }
        result.model if result.success?
      end

      # `nudged` holds the valid document the placement nudge was sent for. If
      # the nudge produces nothing that can be written, that document is
      # written instead of giving up.
      def persist_with_repair(extraction)
        nudged = nil
        (MAX_REPAIR + 1).times do |attempt|
          validation = validate(extraction)
          errors = validation.errors
          if errors.empty? && nudged.nil? && validation.unplaced.any? && repairable?(attempt)
            nudged = [extraction, validation]
            errors = [t("errors.unplaced_uploads", tokens: validation.unplaced.map(&:token).join(", "))]
          elsif errors.empty?
            outcome = guarded { persist(validation.pages) }
            return success(extraction, validation, outcome) if outcome.ok?

            errors = outcome.errors
          end

          repaired = repair.call(document: extraction.as_json, errors: errors) if repairable?(attempt)
          if repaired.nil?
            return nudged ? persist_nudged(*nudged) : give_up(extraction, errors)
          end

          extraction = repaired
        end
      end

      def persist_nudged(extraction, validation)
        outcome = guarded { persist(validation.pages) }
        outcome.ok? ? success(extraction, validation, outcome) : give_up(extraction, outcome.errors)
      end

      def validate(extraction)
        SchemaValidator.call(extraction: extraction, website: @website, uploads: uploads)
      end

      def uploads
        @uploads ||= Uploads.new(conversation: @conversation)
      end

      def repairable?(attempt)
        attempt < MAX_REPAIR && @chat.present? && @conversation.present?
      end

      def repair
        @repair ||= AiAssistant::Assistant::DocumentRepair.new(
          conversation: @conversation,
          chat: @chat,
          mode: :entity,
          instructions: "website_repair",
          parser: Extraction
        )
      end

      def guarded(&operation)
        AiAssistant::Assistant::GenerationWriteGuard.wrap(@write_guard, &operation)
      end

      # Nothing references a copy made for a document that did not save, so it
      # is purged rather than left in the tenant's media.
      def persist(pages)
        copies = []
        urls, errors = import_uploads(pages, copies)
        outcome = errors.any? ? failed(errors) : save_pages(SchemaValidator.map_images(pages) { |value| urls.fetch(value, value) })
        copies.each(&:purge) unless outcome.ok?
        outcome
      rescue StandardError
        copies.each(&:purge)
        raise
      end

      def import_uploads(pages, copies)
        errors = []
        tokens = SchemaValidator.image_values(pages).select { |value| Uploads.token?(value) }.uniq
        urls = tokens.each_with_object({}) do |token, map|
          result = Websites::Activities::ImportMedia.call(customer: @customer, blob: uploads.find(token)&.blob)
          if result.success?
            map[token] = result.url
            copies << result.blob if result.created
          else
            errors << t("errors.import_failed", token: token, message: result.error)
          end
        end
        [urls, errors]
      end

      # Use SavePage's customer boundary for the entire document. It opens a
      # savepoint, so a failed page also rolls back earlier pages under the
      # generation guard. Load existing pages with row locks inside it: draft
      # eligibility, the Undo snapshot and SavePage's reload see the same state.
      def save_pages(pages)
        created = []
        updated = []
        records = []
        undo = []
        errors = []
        PageShortcuts::Collisions.with_customer_lock(customer_id: @customer.id) do
          locked_pages = site_pages.where(id: pages.filter_map { |spec| spec["page_id"] })
                                   .order(:id).lock.index_by(&:id)
          check_generation!
          position = site_pages.maximum(:position).to_i
          pages.each do |spec|
            if spec["page_id"]
              page = revisable_page(spec["page_id"], errors, locked_pages: locked_pages)
            else
              position += 1
              page = WebsitePage.new(website_id: @website.id, customer_id: @customer.id, published: false, position: position)
            end
            next unless page

            before = Undo.snapshot(page) if page.persisted?
            result = Websites::Activities::SavePage.call(page: page, params: page_params(spec), structure_editable: true)
            unless result.success?
              errors << t("errors.save_failed", title: spec["title"], details: Array(result.errors).join(t("detail_separator")))
              next
            end

            (spec["page_id"] ? updated : created) << result.model.title
            records << result.model
            undo << Undo.entry(result.model, before: before)
          end
          check_generation!
          raise ActiveRecord::Rollback if errors.any?
        end
        return failed(errors) if errors.any?

        Outcome.new(created: created, updated: updated, pages: records, undo: undo, errors: [])
      end

      # Validation is preliminary. Only the fresh, locked tenant/site row may
      # supply publication state and the pre-write Undo snapshot.
      def revisable_page(id, errors, locked_pages:)
        page = locked_pages[id.to_i]
        if page.nil?
          errors << t("errors.page_not_found", id: id)
        elsif page.published?
          errors << t("errors.page_published", title: page.title)
        else
          return page
        end
        nil
      end

      def check_generation!
        # The enclosing guard holds the conversation lock before the customer
        # and page locks. Recheck at the write boundary without changing that
        # order; callable-only guards used by replay/specs still enclose it.
        @write_guard.check! if @write_guard.respond_to?(:check!)
      end

      def site_pages
        @website.pages.where(customer_id: @customer.id)
      end

      # Home was decided at validation, which can be a repair round-trip ago:
      # a revision keeps the flag it has, and a new page only becomes home if
      # the site still has none.
      def page_params(spec)
        params = { title: spec["title"], nav_visible: spec["nav_visible"], sections: spec["sections"] }
        params[:slug] = spec["slug"] unless spec["slug"].nil?
        params[:home] = true if spec["home"] && spec["page_id"].nil? && !site_pages.exists?(home: true)
        params
      end

      def failed(errors)
        Outcome.new(created: [], updated: [], pages: [], undo: [], errors: errors)
      end

      def success(extraction, validation, outcome)
        message(
          success_body(extraction.reply, validation.unplaced, outcome),
          intent: extraction.intent,
          applied: true,
          created: outcome.created,
          updated: outcome.updated,
          pages: outcome.pages,
          undo: outcome.undo
        )
      end

      def success_body(reply, unplaced, outcome)
        parts = [reply]
        parts << t("apply_created", names: outcome.created.to_sentence) if outcome.created.any?
        parts << t("apply_updated", names: outcome.updated.to_sentence) if outcome.updated.any?
        parts << t("drafts_note") if outcome.created.any?
        parts << t("unplaced_images", names: unplaced.map(&:filename).to_sentence) if unplaced.any?
        sentences(parts)
      end

      def give_up(extraction, errors)
        details = sentences(Array(errors).map(&:to_s).reject(&:blank?))
        message(sentences([extraction.reply, t("schema_invalid", details: details)]), intent: extraction.intent)
      end

      def sentences(parts)
        parts.join(t("sentence_separator"))
      end

      def t(key, **options)
        I18n.t("ai_assistant.assistant.website.#{key}", **options)
      end

      def message(body, status: "complete", intent: nil, applied: false, created: [], updated: [], pages: [], undo: [])
        Message.new(
          body: body,
          status: status,
          intent: intent,
          applied: applied,
          created: Array(created),
          updated: Array(updated),
          pages: Array(pages),
          undo: Array(undo)
        )
      end
    end
  end
end
