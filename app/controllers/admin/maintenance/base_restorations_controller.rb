# frozen_string_literal: true

module Admin
  module Maintenance
    # Abstract base for "restore a soft-deleted record" actions. Subclasses declare
    # the record source, redirect target, and flash key via `restorable`. The
    # finder and redirect lambdas run in controller context (they can read
    # `params` / `current_customer_id`), so tenant scoping stays in each subclass.
    class BaseRestorationsController < ApplicationController
      dashboard_menu_item :maintenance
      include SharedResourceMode

      class_attribute :record_finder, :redirect_target, :restored_flash_key

      def self.restorable(finder:, redirect:, flash_key:)
        self.record_finder       = finder
        self.redirect_target     = redirect
        self.restored_flash_key  = flash_key
      end

      def update
        record = instance_exec(&record_finder)
        if record.restore
          redirect_to instance_exec(&redirect_target),
                      notice: restored_notice(record)
        else
          message = record.errors.full_messages.to_sentence.presence || t("routes_audit.restoration_failed")
          respond_to do |format|
            format.html { redirect_to instance_exec(&redirect_target), alert: message }
            format.json { render json: { errors: record.errors.full_messages.presence || [message] }, status: :unprocessable_entity }
          end
        end
      end

      private

      # Subclasses may append follow-up guidance to the restored message.
      def restored_notice(record)
        t(restored_flash_key, name: record.name)
      end
    end
  end
end
