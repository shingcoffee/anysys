# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::RatingFieldComponent, type: :component do
  def render_rating(**opts)
    render_inline(described_class.new(**{ field_name: :rating, label: 'Rating' }.merge(opts)))
  end

  it 'renders 5 stars by default' do
    render_rating
    expect(page).to have_css('[data-rating-star]', count: 5)
  end

  it 'renders custom max stars' do
    render_rating(max: 10)
    expect(page).to have_css('[data-rating-star]', count: 10)
  end

  it 'renders with selected value' do
    render_rating(value: 3)
    expect(page).to have_css('[data-rating-star][data-selected="true"]', count: 3)
  end

  it 'renders hidden input for form submission' do
    render_rating
    expect(page).to have_css('input[type="hidden"][name="rating"]', visible: :hidden)
  end
end
