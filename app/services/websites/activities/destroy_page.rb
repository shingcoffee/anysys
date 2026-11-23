# frozen_string_literal: true

module Websites
  module Activities
    class DestroyPage
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(page:)
        if page.home?
          return Result.new(
            success?: false,
            model: page,
            errors: [ I18n.t("website.errors.home_required") ]
          )
        end

        page.destroy!
        Result.new(success?: true, model: page, errors: [])
      end
    end
  end
end
