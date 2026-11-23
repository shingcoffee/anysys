# frozen_string_literal: true

# Stored entity definitions live in content-addressed JSON, not typed columns.
# Attribute type "Rollup" is renamed to "Computed": each changed payload gets a
# new content row, versions are repointed, and unreferenced hashes are swept.
class RewriteEntityAttributeTypeRollupToComputed < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  FROM_TYPE = "Rollup"
  TO_TYPE = "Computed"

  def up
    rewrite_payloads!(FROM_TYPE, TO_TYPE)
  end

  def down
    rewrite_payloads!(TO_TYPE, FROM_TYPE)
  end

  private

  def rewrite_payloads!(from, to)
    customer_ids = []

    EntityDefinitionContent.unscoped.pluck(:id).each_slice(200) do |slice|
      EntityDefinitionContent.unscoped.where(id: slice).find_each do |content|
        payload = parse_payload(content.payload)
        next unless rewrite_types!(payload, from, to)

        new_row = EntityDefinitionContent.store!(customer_id: content.customer_id, payload: payload)
        customer_ids << content.customer_id
        next if new_row.id == content.id

        EntityVersion.unscoped.where(content_id: content.id).update_all(content_id: new_row.id)
      end
    end

    customer_ids.uniq.each do |cid|
      EntityDefinitionContent.sweep_orphans!(customer_id: cid)
    end
  end

  def parse_payload(raw)
    case raw
    when String then JSON.parse(raw)
    when Hash then raw
    else {}
    end
  end

  def rewrite_types!(value, from, to)
    case value
    when Hash
      changed = false
      if value["type"] == from
        value["type"] = to
        changed = true
      end
      value.each_value { |child| changed = true if rewrite_types!(child, from, to) }
      changed
    when Array
      value.reduce(false) { |acc, child| rewrite_types!(child, from, to) || acc }
    else
      false
    end
  end
end
