# frozen_string_literal: true

module Emails
  # Resolves catalog rows for the template builder and TemplateRenderer.
  class TokenCatalog
    TOKEN_UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

    def self.for_customer(customer_id)
      new(customer_id)
    end

    def initialize(customer_id)
      @customer_id = customer_id
    end

    def platform_tokens
      @platform_tokens ||= TemplateToken.platform.order(:label).to_a
    end

    def custom_tokens
      @custom_tokens ||= TemplateToken.custom_for(@customer_id).order(:label).to_a
    end

    def all
      platform_tokens + custom_tokens
    end

    def picker_groups
      # Option value is the human label (not the storage UUID) so the insert
      # picker never surfaces UUIDs in the searchable-select DOM / selection.
      groups = [
        [
          I18n.t("admin_modules.emails.templates.form.token_group_catalog"),
          platform_tokens.map { |t| [editor_label(t), editor_label(t)] }
        ]
      ]
      if custom_tokens.any?
        groups << [
          I18n.t("admin_modules.emails.templates.form.token_group_custom"),
          custom_tokens.map { |t| [editor_label(t), editor_label(t)] }
        ]
      end
      groups
    end

    def find_by_uuid(uuid)
      return nil if uuid.blank?

      by_uuid[uuid.to_s.downcase]
    end

    # Keep human picker values round-trippable even when platform translations
    # and customer-authored labels collide. Stable source identifiers, never
    # storage UUIDs, distinguish the colliding labels.
    def editor_label(token)
      label = token.display_label.to_s
      return label if label_groups.fetch(label.downcase, []).one?

      source = token.platform? ? token.source_key : "#{token.entity_id}.#{token.attribute_slug}"
      "#{label} (#{source})"
    end

    def label_index
      # A hand-authored label can itself resemble a qualified label. Never pick
      # a winner for such an ambiguity, including case-insensitive collisions.
      all.group_by { |token| editor_label(token).downcase }.each_with_object({}) do |(label, tokens), index|
        index[label] = tokens.first.uuid if tokens.one?
      end
    end

    # Builds the UUID → resolved string map for a send/preview.
    # Custom entity_attribute values are blank until User↔EntityEntry exists.
    def resolve_vars(context_hash)
      context_hash = stringify_keys_deep(context_hash)
      all.each_with_object({}) do |token, out|
        out[token.uuid] = resolve_token(token, context_hash)
      end
    end

    private

    def label_groups
      @label_groups ||= all.group_by { |token| token.display_label.to_s.downcase }
    end

    def by_uuid
      @by_uuid ||= all.index_by { |t| t.uuid.downcase }
    end

    def resolve_token(token, context_hash)
      case token.source_type
      when TemplateToken::SOURCE_PLATFORM
        val = resolve_path(token.source_key, context_hash)
        if val.nil? && token.source_key.start_with?("authentication_user.")
          flat_key = token.source_key.sub(/\Aauthentication_user\./, "")
          val = context_hash[flat_key] || context_hash[flat_key.to_sym]
        end
        val.to_s
      when TemplateToken::SOURCE_ENTITY
        "" # deferred: recipient EntityEntry linkage not wired yet
      else
        ""
      end
    end

    def resolve_path(path, hash)
      return nil if path.blank?

      path.to_s.split(".").inject(hash) do |current, key|
        break nil unless current.is_a?(Hash)

        current[key] || current[key.to_sym]
      end
    end

    def stringify_keys_deep(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_deep(v) }
      else
        value
      end
    end
  end
end
