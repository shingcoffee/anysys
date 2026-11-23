# frozen_string_literal: true

module Emails
  class DateRangePickerComponent < ApplicationComponent
    attr_reader :url, :since, :until_date, :submit_label

    def initialize(url:, since: nil, until_date: nil, submit_label: nil)
      @url          = url
      @since        = since
      @until_date   = until_date
      @submit_label = submit_label
    end
  end
end
