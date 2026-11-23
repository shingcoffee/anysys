# frozen_string_literal: true

module Member
  module Navigation
    # Value object describing a single member nav item.
    #
    # @!attribute [r] key       Symbol — used by the shell to mark active state.
    # @!attribute [r] label     String — display text.
    # @!attribute [r] icon      Symbol — Heroicons identifier (rendered by views).
    # @!attribute [r] path      Proc  — callable taking a Customer, returning a URL string.
    # @!attribute [r] visible   Proc  — callable taking a User, returning a Boolean.
    Item = Struct.new(:key, :label, :icon, :path, :visible, keyword_init: true) do
      def path_for(customer)
        path.call(customer)
      end

      def visible_to?(user)
        visible.call(user)
      end
    end
  end
end
