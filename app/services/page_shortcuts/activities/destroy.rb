# frozen_string_literal: true

module PageShortcuts
  module Activities
    class Destroy
      def self.call(shortcut:, customer_id:)
        shortcut.errors.clear
        cid = PathPolicy.customer_id(customer_id)
        if cid && shortcut.persisted? && shortcut.customer_id == cid &&
            PageShortcut.for_customer(cid).exists?(id: shortcut.id)
          shortcut.destroy!
          Save::Result.new(success?: true, model: shortcut, errors: {})
        else
          shortcut.errors.add(:base, I18n.t("page_shortcuts.errors.invalid_customer"))
          Save::Result.new(success?: false, model: shortcut, errors: shortcut.errors.messages.to_h)
        end
      end
    end
  end
end
