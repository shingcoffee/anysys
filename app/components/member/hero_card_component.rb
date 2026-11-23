# frozen_string_literal: true

module Member
  class HeroCardComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(greeting:, name:, subhead:, status: nil)
      @greeting = greeting
      @name     = name
      @subhead  = subhead
      @status   = status
    end

    attr_reader :greeting, :name, :subhead, :status
  end
end
