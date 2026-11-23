# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Backfill reserved roles for every existing customer (idempotent).
Customer.find_each do |c|
  Roles::Operation::SeedReserved.call(customer: c)
end

puts "Seeded reserved roles for #{Customer.count} customers"

Emails::PlatformTokenSeeds.ensure!
puts "Ensured #{Emails::TemplateToken.platform.count} platform email template variables"

Oauth::DesktopClient.ensure!
puts "Ensured OAuth desktop client #{Oauth::Protocol::CLIENT_ID}"

# Restore only a missing platform-owner site. Existing builder edits are kept;
# explicit source updates use Websites::HomeSite.apply!(locale: :en).
if Customer.exists?(id: Websites::HomeSite::CUSTOMER_ID) &&
    !Website.exists?(customer_id: Websites::HomeSite::CUSTOMER_ID)
  Websites::HomeSite.apply!
  puts "Ensured the platform-owner marketing site at /#{Websites::HomeSite::CUSTOMER_ID}/site"
end
