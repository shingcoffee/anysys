# frozen_string_literal: true

module Pages
  # The only lookup from an action key to the live page for an audience.
  # A tenant page wins over a shared page with the same key and audience.
  class ActionResolver
    class << self
      def page_for(customer_id:, action_key:, audience:)
        return if action_key.blank?

        audience = audience.to_s
        return unless PageVisibility::AUDIENCES.include?(audience)

        scope = Page.where(action_key: action_key, launched: true).for_audience(audience).order(:id)
        if customer_id.present?
          scope.find_by(customer_id: customer_id) || scope.find_by(customer_id: nil)
        else
          scope.find_by(customer_id: nil)
        end
      end

      # page_for for several action keys in one query: { action_key => page }.
      def pages_for(customer_id:, action_keys:, audience:)
        keys = Array(action_keys).compact_blank.uniq
        audience = audience.to_s
        return {} if keys.empty? || !PageVisibility::AUDIENCES.include?(audience)

        owners = customer_id.present? ? [customer_id, nil] : [nil]
        pages = Page.where(action_key: keys, launched: true, customer_id: owners).for_audience(audience).order(:id).to_a
        pages.group_by(&:action_key).transform_values do |list|
          list.find { |page| page.customer_id.present? } || list.first
        end
      end

      # customer_id is the visited tenant: a shared page yields to that tenant's page.
      def counterpart(page:, audience:, customer_id: page.customer_id)
        return if page.action_key.blank?

        found = page_for(customer_id: customer_id, action_key: page.action_key, audience: audience)
        found unless found.nil? || found.id == page.id
      end

      def siblings(page)
        return Page.none if page.action_key.blank?

        Page.where(action_key: page.action_key, customer_id: page.customer_id).where.not(id: page.id)
      end
    end
  end
end
