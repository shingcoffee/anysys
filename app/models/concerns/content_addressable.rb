# frozen_string_literal: true

# Immutable, content-addressed payload store shared by the three *_contents
# models. A payload is stored once, keyed by (customer_id, SHA-256 of its
# canonical JSON). Rows are never updated — only created (find-or-create) and
# garbage-collected when no version references them.
module ContentAddressable
  extend ActiveSupport::Concern

  class_methods do
    # Deterministic serialization: keys sorted recursively so that two equal
    # definitions hash identically regardless of key order.
    def canonical_json(value)
      JSON.generate(deep_sort(value))
    end

    def digest(payload)
      Digest::SHA256.hexdigest(canonical_json(payload))
    end

    # Find-or-create the content row for this payload. Idempotent; retries the
    # narrow unique-index race (matches Versionable's RecordNotUnique handling).
    def store!(customer_id:, payload:)
      hash = digest(payload)
      attempts = 0
      begin
        attempts += 1
        find_by(customer_id: customer_id, content_hash: hash) ||
          create!(customer_id: customer_id, content_hash: hash,
                  payload: canonical_json(payload))
      rescue ActiveRecord::RecordNotUnique
        retry if attempts < 3
        find_by!(customer_id: customer_id, content_hash: hash)
      end
    end

    # Delete content rows for this tenant no longer referenced by any version.
    def sweep_orphans!(customer_id:)
      version_klass = reflect_on_association(version_association).klass
      referenced = version_klass.where(customer_id: customer_id).select(:content_id)
      where(customer_id: customer_id).where.not(id: referenced).delete_all
    end

    private

    def deep_sort(value)
      case value
      when Hash  then value.keys.sort_by(&:to_s).to_h { |k| [k, deep_sort(value[k])] }
      when Array then value.map { |v| deep_sort(v) }
      else value
      end
    end
  end
end
