# frozen_string_literal: true

module Sms
  module Admin
    class CampaignPreviewComponent < BaseComponent
      def initialize(preview:, contacts:, selected_contact_id: nil)
        @preview, @contacts, @selected_contact_id = preview, Array(contacts).first(20), selected_contact_id
      end
    end
  end
end
