# frozen_string_literal: true

# Resolves the public website theme for member pages. /:cid/member uses the
# same tokens as /:cid/site. Missing website → site defaults.
module MemberChromeHelper
  def member_site_theme
    return @member_site_theme if defined?(@member_site_theme) && @member_site_theme

    customer_id = member_theme_customer_id
    tokens = customer_id && Website.find_by(customer_id: customer_id)&.theme
    @member_site_theme = Websites::Theme.new(tokens)
  end

  def member_chrome
    @member_chrome ||= Member::Chrome.new(member_site_theme)
  end

  private

  def member_theme_customer_id
    customer = member_theme_current(:current_customer)
    return customer.id if customer.respond_to?(:id) && customer.id

    user = member_theme_current(:current_user)
    user.customer_id if user.respond_to?(:customer_id)
  end

  # Component specs render without Warden. Devise's current_user raises there;
  # a missing session means the public-site defaults.
  def member_theme_current(name)
    return unless respond_to?(name)

    public_send(name)
  rescue Devise::MissingWarden
    nil
  end
end
