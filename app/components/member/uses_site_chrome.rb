# frozen_string_literal: true

module Member
  # Lets a member component read the public-site chrome for this request.
  module UsesSiteChrome
    def chrome
      helpers.member_chrome
    end
  end
end
