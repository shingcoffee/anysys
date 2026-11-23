# frozen_string_literal: true

module People
  # Thin facade for linking a person-entity entry to a User. Writes go through
  # Activities::Link; reads (candidates) live here so
  # controllers share one name. Member row scope is People::Ownership.scope.
  class Link
    Result = Struct.new(:success?, :entry, :errors, keyword_init: true)

    def self.link!(entry:, user_id:, actor:, event: "person.linked")
      Activities::Link.call(entry: entry, user_id: user_id, actor: actor, event: event)
    end

    # Active users in the entry's tenant who are not already linked to any
    # entry of this entity. Blank query returns the first `limit` by name.
    def self.candidates(entry:, query:, limit: 20)
      scope = Authentication::User.where(customer_id: entry.customer_id, status: :active)
      linked_ids = EntityEntry.where(entity_id: entry.entity_id).where.not(user_id: nil).select(:user_id)
      scope = scope.where.not(id: linked_ids)

      q = query.to_s.strip
      if q.present?
        like = "%#{Authentication::User.sanitize_sql_like(q.downcase)}%"
        scope = scope.where(
          "LOWER(first_name) LIKE ? ESCAPE '\\' OR LOWER(last_name) LIKE ? ESCAPE '\\' OR LOWER(email) LIKE ? ESCAPE '\\'",
          like, like, like
        )
      end

      scope.order(:last_name, :first_name).limit(limit).to_a
    end

    # Copies the account's identity back into the entry's data and clears the
    # link, so the entry keeps a name and email once it stops being linked.
    def self.detach!(entry, user = entry.user)
      data = entry.data_json.is_a?(Hash) ? entry.data_json.stringify_keys : {}
      IDENTITY_KEYS.each { |key| data[key] = user.public_send(key) } if user
      entry.user_id = nil
      entry.data_json = data
      entry.save!(validate: false)
    end
  end
end
