# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      # Everything a prompt section is allowed to read. Sections receive this
      # and nothing else, so adding a section never widens their reach into the
      # conversation or the request.
      class Context
        attr_reader :conversation, :mode

        def initialize(conversation:, mode:)
          @conversation = conversation
          @mode = mode.to_sym
        end

        def customer_id
          conversation.customer_id
        end

        def customer
          conversation.customer
        end

        # Live customer-owned entity definitions for this tenant, in the
        # public vocabulary the operations speak.
        def entity_catalog
          @entity_catalog ||= begin
            mapper = EntityDefinitions::Api::Mapper.new(customer: customer)
            Entity.where(customer_id: customer_id)
                  .non_bridge
                  .by_name
                  .includes(current_version: :content)
                  .map { |entity| mapper.from_entity(entity) }
          end
        end

        # Customer-owned domains and the non-bridge entities placed in each.
        def domain_catalog
          @domain_catalog ||= begin
            domains = EntityDomain.for_customer(customer_id).by_name.to_a
            memberships = EntityDomainMembership.for_customer(customer_id)
                                                .where(entity_domain_id: domains.map(&:id))
            names_by_id = Entity.where(customer_id: customer_id, id: memberships.map(&:entity_id))
                                .non_bridge
                                .pluck(:id, :name)
                                .to_h
            grouped = memberships.group_by(&:entity_domain_id)
            domains.map do |domain|
              {
                "name" => domain.name,
                "description" => domain.description,
                "color" => domain.color,
                "entities" => Array(grouped[domain.id]).filter_map { |row| names_by_id[row.entity_id] }
              }
            end
          end
        end

        def native_tools?
          settings = AiAssistant::ProviderSettings.active_for(:generation)
          settings&.provider_class&.supports_native_tools? == true
        end

        def operations_context
          @operations_context ||= Operations::Context.new(
            customer: customer,
            actor: conversation.user,
            channel: "assistant",
            conversation: conversation
          )
        end

        def flowchart_catalog
          return [] unless flowchart_visible?

          @flowchart_catalog ||= FlowchartDefinitions::Catalog.for_customer(customer_id)
        end

        def flowchart_visible?
          FlowchartVisibility.allowed?(conversation.user)
        end

        def mentions
          @mentions ||= Mentions.resolve(
            body: latest_user_body,
            customer_id: customer_id,
            viewer: conversation.user
          )
        end

        # The entity this turn is about, if any.
        #
        # A mention replaces the workspace pin outright rather than falling
        # back to it: once the admin has named something, pointing the model at
        # whatever happens to be on screen would contradict the mention. So a
        # turn that mentions only a flowchart has no focused entity at all.
        def focused_entity
          return @focused_entity if defined?(@focused_entity)

          @focused_entity = mentions.any? ? mentioned_entity : pinned_entity
        end

        def website_enabled?
          return @website_enabled if defined?(@website_enabled)

          @website_enabled = FeatureModules::Website::Registration.enabled_for?(customer_id)
        end

        def website
          return @website if defined?(@website)

          @website = Website.find_by(customer_id: customer_id)
        end

        def website_pages
          @website_pages ||= website ? website.pages.where(customer_id: customer_id).reorder(:position, :id).to_a : []
        end

        # The website page pinned to the workspace preview. Artifact.resolve
        # already drops it once the Website module is off.
        def focused_website_page
          resolved = pinned_artifact
          resolved.record if resolved&.kind == "website_page"
        end

        # Images the admin attached in this conversation, addressable by token.
        def uploads
          @uploads ||= Websites::Assistant::Uploads.new(conversation: conversation)
        end

        # The parked update the admin has not yet approved, when it is still
        # live for this conversation. Nil for flowchart proposals, settled
        # invocations, and rows that do not belong to this tenant or thread.
        def pending_operation_proposal
          return @pending_operation_proposal if defined?(@pending_operation_proposal)

          @pending_operation_proposal = find_pending_operation_proposal
        end

        private

        # The first entity named, which is the subject when several are (as in
        # "bridge @Student to @Course").
        def mentioned_entity
          mentions.find { |mention| mention.kind == "entity" }&.record
        end

        def pinned_entity
          resolved = pinned_artifact
          return nil unless resolved

          case resolved.kind
          when "entity" then resolved.record
          when "page" then resolved.record.entity
          end
        end

        def pinned_artifact
          return @pinned_artifact if defined?(@pinned_artifact)

          @pinned_artifact = Artifact.resolve(conversation, customer: customer, viewer: conversation.user)
        end

        def latest_user_body
          conversation.messages.where(role: "user").order(:id).last&.body
        end

        def find_pending_operation_proposal
          message = conversation.messages.where(role: "assistant").with_pending_proposal.order(id: :desc).first
          proposal = message&.metadata_json&.[]("pending_confirmation")
          return unless proposal.is_a?(Hash) && proposal["kind"].to_s == "operation"

          invocation = OperationInvocation.find_by(
            id: proposal["invocation_id"],
            customer_id: customer_id,
            conversation_id: conversation.id
          )
          return unless invocation&.awaiting_confirmation?

          { "operation" => invocation.operation, "input" => invocation.input }
        end
      end
    end
  end
end
