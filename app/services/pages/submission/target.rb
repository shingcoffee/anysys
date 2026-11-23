# frozen_string_literal: true

module Pages
  module Submission
    # The record a page submission writes and whether it creates or updates
    # it. An update names an entry an admin may edit (tenant- and
    # entity-scoped), or for a member a row they manage from their own record
    # (Pages::MemberRows) or the record their journey run's current update
    # step edits (+journey_record_id+, only while the member still reaches
    # it), or — on an update-only page — the signed-in member's own person
    # record. Anything else is refused before the flowchart runs.
    Target = Data.define(:mode, :record) do
      def create? = mode == :create
    end

    class Target
      ENTRY_ID = /\A[1-9]\d*\z/

      Refusal = Data.define(:http_status, :message_key)

      # A Target, or a Refusal when the page doesn't take this submission.
      def self.resolve(page:, entity:, entry_id:, audience:, viewer:, customer_id:, journey_record_id: nil)
        Resolver.new(page, entity, entry_id.presence, audience, viewer, customer_id, journey_record_id.presence).call
      end

      class Resolver
        def initialize(page, entity, entry_id, audience, viewer, customer_id, journey_record_id)
          @page = page
          @entity = entity
          @entry_id = entry_id
          @audience = audience
          @viewer = viewer
          @customer_id = customer_id
          @journey_record_id = journey_record_id
        end

        def call
          return Refusal.new(:method_not_allowed, "common.errors.dynamic.page_not_executable") unless @page.serves?(mode)
          return Target.new(mode: :create, record: new_record) if mode == :create

          record = @entry_id ? edited_entry : own_person_entry
          record ? Target.new(mode: :update, record: record) : Refusal.new(:not_found, "common.errors.dynamic.entry_unavailable")
        end

        private

        def mode
          @mode ||= @entry_id || (!@page.serves?(:create) && own_person_entry) ? :update : :create
        end

        def entries = EntityEntry.build_for(@entity)

        def new_record = entries.new(entity: @entity, customer_id: @customer_id)

        def edited_entry
          return unless @entry_id.to_s.match?(ENTRY_ID)

          case @audience
          when EntityAttributeAudience::ADMIN
            entries.find_by(id: @entry_id, customer_id: @customer_id, entity_id: @entity.id)
          when EntityAttributeAudience::MEMBER
            Pages::MemberRows.row(page: @page, entry_id: @entry_id, viewer: @viewer, customer_id: @customer_id) || journey_entry
          end
        end

        def journey_entry
          return unless @journey_record_id.to_s == @entry_id.to_s
          return unless People::Ownership.reachable_ids(@entity, [@entry_id], viewer: @viewer, audience: EntityAttributeAudience::MEMBER,
                                                                               customer_id: @customer_id).include?(@entry_id.to_s)

          entries.find_by(id: @entry_id, customer_id: @customer_id, entity_id: @entity.id)
        end

        def own_person_entry
          return @own_person_entry if defined?(@own_person_entry)
          return @own_person_entry = nil unless @audience == EntityAttributeAudience::MEMBER && @entity.person?

          id = People::Ownership.person_entry_id(@viewer, @entity.id)
          @own_person_entry = id && entries.find_by(id: id, customer_id: @customer_id, entity_id: @entity.id)
        end
      end
      private_constant :Resolver
    end
  end
end
