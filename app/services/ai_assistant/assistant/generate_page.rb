# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Builds and launches an admin-only tenant form from an entity's current version. Wraps
    # Pages::Activities::CreateFromEntityVersion so the assistant can finish
    # the entity → page loop without mutating shared rows.
    class GeneratePage
      Result = Struct.new(:ok, :page, :skipped, :message, :created, keyword_init: true)

      def self.call(entity:, customer:)
        new(entity: entity, customer: customer).call
      end

      def initialize(entity:, customer:)
        @entity = entity
        @customer = customer
      end

      def call
        return skip(:no_customer) if @customer.blank? || @entity.blank?
        return skip(:wrong_tenant) unless @entity.customer_id == @customer.id

        version = @entity.current_version
        return skip(:no_version) unless version

        result = nil
        Page.transaction(requires_new: true) do
          result = generate_and_launch(version)
          raise ActiveRecord::Rollback unless result.ok
        end
        result
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        reason = e.record&.errors&.full_messages&.to_sentence.presence ||
                 I18n.t("ai_assistant.assistant.apply_errors.page_launch_failed")
        Result.new(
          ok: false,
          skipped: :launch_failed,
          message: I18n.t("ai_assistant.assistant.apply_page_skipped", reason: reason)
        )
      end

      private

      def generate_and_launch(version)
        result = Pages::Activities::CreateFromEntityVersion.call(
          entity: @entity,
          version: version,
          customer: @customer,
          shared: false
        )
        if result.success?
          key_as_create_page(result.page)
          bind_processing(result.page)
          result.page.launch!
          Result.new(
            ok: true,
            page: result.page,
            created: result.page.name,
            message: I18n.t("ai_assistant.assistant.apply_page_created", names: result.page.name)
          )
        elsif result.error_code == :page_exists
          page = existing_page(version)
          Result.new(ok: true, page: page, skipped: :page_exists)
        else
          Result.new(ok: false, skipped: result.error_code, message: result.message)
        end
      end

      # Keyed like the journey generator's create page, so a journey built on
      # this entity's domain reuses this form instead of composing another.
      def key_as_create_page(page)
        return if page.action_key.present?

        key = Pages::ActionKeys.unique(EntityDomains::JourneyPlanner.create_page_key(@entity), customer_id: @customer.id)
        page.update_columns(action_key: key)
      end

      # A page created after the platform owner deleted the shared "Save page
      # record" starts unbound and could not launch.
      def bind_processing(page)
        page.update!(flowchart: Flowcharts::DefaultPageFlowchart.for_customer(@customer)) unless page.flowchart
      end

      def existing_page(version)
        Page.where(customer_id: @customer.id, entity_version_id: version.id).first
      end

      def skip(code)
        Result.new(ok: false, skipped: code, message: skip_message(code))
      end

      def skip_message(code)
        case code
        when :no_version
          I18n.t("ai_assistant.assistant.apply_page_skipped", reason: I18n.t("ai_assistant.assistant.apply_errors.page_version_missing"))
        when :wrong_tenant, :no_customer
          I18n.t("ai_assistant.assistant.apply_errors.no_customer")
        else
          I18n.t("ai_assistant.assistant.apply_page_skipped", reason: code.to_s)
        end
      end
    end
  end
end
