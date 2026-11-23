# frozen_string_literal: true

require "rails_helper"

# Area-a billing URLs were removed when management moved under
# admin/settings/billing/*. Keep the 404s so old bookmarks do not silently
# succeed. Live coverage lives in spec/requests/admin/settings/billing/.
RSpec.describe "admin/modules/billing (removed routes)", type: :request do
  it_behaves_like "a removed admin URL", "/admin/modules/billing/subscription"
  it_behaves_like "a removed admin URL", "/admin/modules/billing/invoices"
  it_behaves_like "a removed admin URL", "/admin/modules/billing/invoices/1"
end
