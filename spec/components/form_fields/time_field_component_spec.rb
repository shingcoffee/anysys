# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::TimeFieldComponent, type: :component do
  # Defaults to a labelled "Start Time" field; override any arg.
  def render_time(**opts)
    render_inline(described_class.new(**{ field_name: :start_time, label: 'Start Time' }.merge(opts)))
  end

  it 'renders time input' do
    render_time
    expect(page).to have_css('input[type="time"]')
  end

  it 'renders with value' do
    render_time(value: '14:30')
    expect(page).to have_field('Start Time', with: '14:30')
  end

  it 'renders with min/max constraints' do
    render_time(min: '09:00', max: '17:00')
    expect(page).to have_css('input[min="09:00"]')
    expect(page).to have_css('input[max="17:00"]')
  end

  it 'renders with step attribute' do
    render_time(step: '900')
    expect(page).to have_css('input[step="900"]')
  end

  it 'renders with all three constraints together' do
    render_time(field_name: :meeting_time, label: 'Meeting Time', min: '08:00', max: '18:00', step: '1800')
    expect(page).to have_css('input[type="time"][min="08:00"][max="18:00"][step="1800"]')
  end

  it 'omits min attribute when not provided' do
    render_time
    expect(page).to have_no_css('input[min]')
  end

  it 'omits max attribute when not provided' do
    render_time
    expect(page).to have_no_css('input[max]')
  end

  it 'omits step attribute when not provided' do
    render_time
    expect(page).to have_no_css('input[step]')
  end

  it 'renders as required when required: true' do
    render_time(required: true)
    expect(page).to have_css('input[required]')
  end

  # The private methods below are dead code: TimeFieldComponent owns its own ERB
  # template which renders <input type="time"> directly (with ERB min/max/step
  # conditionals), bypassing BaseFieldComponent#render_input which is the only
  # caller of `input_attributes`. These tests call the methods directly to reach
  # lines 16-26 (field_type, input_attributes) that are otherwise unreachable.
  describe "private interface (dead code — template bypasses BaseFieldComponent)" do
    let(:component) { described_class.new(field_name: :start_time, label: 'Start Time', min: '08:00', max: '18:00', step: '900') }

    it "field_type returns :time" do
      expect(component.send(:field_type)).to eq(:time)
    end

    it "input_attributes sets type to time and includes min/max/step" do
      attrs = component.send(:input_attributes)
      expect(attrs[:type]).to eq('time')
      expect(attrs[:min]).to eq('08:00')
      expect(attrs[:max]).to eq('18:00')
      expect(attrs[:step]).to eq('900')
    end

    it "input_attributes omits min/max/step when absent" do
      c = described_class.new(field_name: :start_time, label: 'Start Time')
      attrs = c.send(:input_attributes)
      expect(attrs).not_to have_key(:min)
      expect(attrs).not_to have_key(:max)
      expect(attrs).not_to have_key(:step)
    end
  end
end
