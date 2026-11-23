# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        # Platform-owner configuration for countable items (Area d).
        #
        # Manages the registry of countable items (pages, entities, members,
        # communications, etc.) that may be used as billing plan limits.
        # Authorization is inherited from
        # BaseController via RouteAuthorization (platform-owner + customer 81721200 only).
        class CountableItemsController < BaseController
          # GET /:cid/admin/maintenance/platform/billing/countable_items
          #
          # Inspection does not seed or change the catalog.
          def show
            @items = ::Billing::CountableItem.ordered
          end

          # PATCH /:cid/admin/maintenance/platform/billing/countable_items
          #
          # Accepts a collection of item attributes keyed by id or key and
          # bulk-upserts label, enabled, and position. The key itself is
          # registry-derived and cannot be changed by users.
          def update
            @submitted_items = submitted_items.map(&:to_h)
            result = ::Billing::Catalog::UpdateCountableItems.call(items: @submitted_items)
            unless result.status == :saved
              @items = ::Billing::CountableItem.ordered
              return render_billing_failure(result, :show)
            end
            redirect_to admin_maintenance_platform_billing_countable_items_path(current_customer_id),
                        status: :see_other,
                        notice: t("maint_platform.flash.billing.countable_items_updated")
          end

          private

          def countable_items_params
            params.permit(items: %i[id label enabled position description unit category period])
          end

          # Normalizes the permitted `items` collection into an array of attribute
          # hashes. The form submits indexed fields (items[0][id], items[1][id], …)
          # which Rails parses into a hash keyed by index ({ "0" => {…}, "1" => {…} });
          # a JSON/array client may instead submit a plain array. `Array()` on a
          # Parameters hash wraps the whole hash in a single element (yielding a nil
          # id), so we explicitly take its values when given a hash.
          def submitted_items
            items = countable_items_params[:items]
            return [] if items.blank?

            items.respond_to?(:values) ? items.values : Array(items)
          end
        end
      end
    end
  end
end
