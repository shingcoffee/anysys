# frozen_string_literal: true

module Billing
  module Countable
    ItemDefinition = Struct.new(:key, :counter, keyword_init: true) do
      def count_for(customer) = counter.call(customer)
      def default_period = "total"
      def default_label = I18n.t("comp_billing.countable_items.#{key}.label")
      def default_description = I18n.t("comp_billing.countable_items.#{key}.description")
      def default_unit = I18n.t("comp_billing.countable_items.#{key}.unit")
      def default_category
        category_key = key == "member" ? "platform" : "content"
        I18n.t("comp_billing.countable_items_form.category.#{category_key}")
      end
    end
  end
end
