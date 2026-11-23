# frozen_string_literal: true

module Admin
  module Settings
    class MemberHubCardComponent < ApplicationComponent
      attr_reader :presenter
      def initialize(presenter:) ; @presenter = presenter ; end

      def cta_label   ; presenter.editable? ? I18n.t("comp_admin.member_hub_card.configure") : I18n.t("common.actions.view") ; end
      def cta_classes ; "btn btn-secondary shrink-0" ; end
    end
  end
end
