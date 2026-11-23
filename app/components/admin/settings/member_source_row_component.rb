# frozen_string_literal: true

module Admin
  module Settings
    class MemberSourceRowComponent < ApplicationComponent
      attr_reader :presenter, :editable, :customer
      def initialize(presenter:, editable:, customer:)
        @presenter = presenter
        @editable  = editable
        @customer  = customer
      end

      def edit_path
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}/surfaces/#{presenter.surface_key}"
      end

      def update_path
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}"
      end
    end
  end
end
