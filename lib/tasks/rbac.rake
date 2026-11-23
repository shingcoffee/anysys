# frozen_string_literal: true

namespace :rbac do
  desc "Seed grant rows for the reserved admin and member roles across all customers"
  task seed_reserved_grants: :environment do
    Customer.find_each do |customer|
      Current.access_points_catalog = nil
      catalog = AccessPoints::Catalog.for(customer_id: customer.id)
      admin   = customer.roles.find_by(key: "admin")
      member  = customer.roles.find_by(key: "member")
      next if admin.nil? || member.nil?

      ActiveRecord::Base.transaction do
        admin.role_permissions.delete_all
        catalog.groups.each do |group|
          next if group[:key] == "platform" || group[:key].start_with?("admin.maintenance.platform")

          group[:descriptors].each do |d|
            d.actions.each do |action|
              admin.role_permissions.create!(
                subject_type: d.subject_type,
                subject_key:  d.subject_key,
                subject_id:   d.subject_id,
                action:       action.to_s
              )
            end
          end
        end

        member.role_permissions.delete_all
        # Member: no admin-area grants by default. Customer can edit later.
      end

      Current.access_points_catalog = nil
      print "."
    end
    puts " done"
  end
end
