# frozen_string_literal: true

module Entities
  # Entity-specific promotion. Validation and bridge reconciliation happen in
  # one transaction before the head moves; generic page/flowchart promotion is
  # deliberately not involved.
  class PromoteVersion
    Result = Struct.new(:ok, :entity, :version, :errors, keyword_init: true) do
      def success? = ok
    end

    def self.call(entity:, version:, restore: false)
      new(entity: entity, version: version, restore: restore).call
    end

    def initialize(entity:, version:, restore:)
      @entity, @version, @restore = entity, version, restore
    end

    def call
      promoted = nil
      @entity.class.transaction(requires_new: true) do
        @entity.class.unscoped.where(id: @entity.id).lock.pick(:id)
        @entity.reload
        unless @entity.current_line_versions.exists?(id: @version.id)
          @entity.errors.add(:current_version, :invalid)
          raise ActiveRecord::RecordInvalid, @entity
        end

        snapshot = JSON.parse(@version.payload)
        form = Contracts::Definition.new(OpenStruct.new)
        unless form.validate(definition: snapshot)
          form.errors.full_messages.each { |message| @entity.errors.add(:base, message) }
          raise ActiveRecord::RecordInvalid, @entity
        end

        normalized = form.normalized_attributes
        snapshot = snapshot.merge(normalized.stringify_keys.except("referenced_template"))
        if normalized.key?(:referenced_template) && normalized[:referenced_template]
          snapshot["referenced_template"] = normalized[:referenced_template].to_json
        end

        previous = @entity.associations_list.deep_dup
        apply_snapshot(snapshot)
        raise ActiveRecord::RecordInvalid, @entity unless @entity.valid?(:promotion_candidate)
        unless @entity.sync_bridge_entities!(persist: false, previous_associations: previous)
          raise ActiveRecord::RecordInvalid, @entity
        end
        raise ActiveRecord::RecordInvalid, @entity unless @entity.valid?

        # Bridge ids are server-derived. If reconciliation repairs historical
        # ids, create an accurate head rather than pointing at a stale payload.
        reconciled = JSON.parse(@entity.definition_snapshot_json)
        changed = reconciled != snapshot
        if @restore || changed
          description = I18n.t("maint_core.version_descriptions.restored_from", number: @version.version_number)
          promoted = @entity.commit_version!(description: description, based_on_version_id: @version.id)
        else
          @entity.send(:promote_validated_line_head!, @version)
          promoted = @version
        end
        @entity.reload
      end
      Result.new(ok: true, entity: @entity, version: promoted, errors: [])
    rescue JSON::ParserError, TypeError
      @entity.errors.add(:property_schema, :invalid)
      failure
    rescue ActiveRecord::RecordInvalid => error
      @entity.errors.merge!(error.record.errors) unless error.record.equal?(@entity)
      failure
    rescue ActiveRecord::RecordNotUnique
      @entity.errors.add(:associations, :taken)
      failure
    end

    private

    def apply_snapshot(snapshot)
      { property_schema: [], default_properties: {}, associations: [], attribute_groups: [] }.each do |attribute, default|
        value = snapshot.key?(attribute.to_s) ? snapshot[attribute.to_s] : default
        @entity.public_send("#{attribute}_json=", value)
      end
      @entity.icon = snapshot.fetch("icon", "custom")
      @entity.color = snapshot.fetch("color", "#6366f1")
      @entity.description = snapshot["description"]
      @entity.referenced_template = snapshot["referenced_template"]
    end

    def failure
      errors = @entity.errors.dup
      @entity.reload
      @entity.errors.copy!(errors)
      Result.new(ok: false, entity: @entity, version: nil, errors: @entity.errors.full_messages)
    end
  end
end
