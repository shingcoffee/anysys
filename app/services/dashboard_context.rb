# frozen_string_literal: true

DashboardContext = Struct.new(
  :current_user, :current_customer, :current_menu_item, :request_path,
  keyword_init: true
) do
  def customer_id = current_customer&.id
end
