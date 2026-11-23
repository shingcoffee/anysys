# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      # Assembles the system prompt from an ordered list of sections.
      #
      # The running order below IS the prompt outline, and it is the only place
      # that changes when a section is added, removed or moved. Sections are
      # independent: each renders from {Context} alone and drops itself when it
      # has nothing to contribute.
      class Composer
        # Ordering rationale: identity first, then what the platform can do,
        # then the machine contract, then how to apply it, then examples, and
        # finally the tenant's own data so the most situational context sits
        # closest to the conversation.
        OUTLINES = {
          entity: [
            Sections::Role,
            Sections::EntityPlatform,
            Sections::EntityCapabilities,
            Sections::OperationTools,
            Sections::Clarifying,
            Sections::EntityAuthoring,
            Sections::EntityExamples,
            Sections::PageProcessing,
            Sections::SubsystemBuilds,
            Sections::FlowchartHandoff,
            Sections::WebsiteSectionKit,
            Sections::WebsiteContract,
            Sections::WebsiteAuthoring,
            Sections::EntityCatalog,
            Sections::EntityFocus,
            Sections::PendingProposal,
            Sections::WebsiteCatalog,
            Sections::WebsiteImages,
            Sections::Mentions
          ].freeze,
          flowchart: [
            Sections::Role,
            Sections::FlowchartContract,
            Sections::EntityCatalog,
            Sections::FlowchartCatalog,
            Sections::Mentions
          ].freeze
        }.freeze

        MODES = OUTLINES.keys.freeze

        def self.call(context:)
          new(context: context).call
        end

        def initialize(context:)
          @context = context
          @outline = OUTLINES.fetch(context.mode) do
            raise ArgumentError, "unsupported prompt mode: #{context.mode}"
          end
        end

        # @return [String] the system message content
        def call
          @outline.filter_map { |section| section.new(@context).render }.join("\n\n")
        end
      end
    end
  end
end
