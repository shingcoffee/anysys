# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::ArrayItemToolbarComponent, type: :component do
  it "renders move, duplicate, and remove actions" do
    render_inline(described_class.new)

    expect(page).to have_css("[data-action='click->website-builder#moveItemUp']")
    expect(page).to have_css("[data-action='click->website-builder#moveItemDown']")
    expect(page).to have_css("[data-action='click->website-builder#duplicateItem']")
    expect(page).to have_css("[data-remove-item][data-action='click->website-builder#removeItem']")
    expect(page).not_to have_css("[data-remove-item][disabled]")
  end

  it "disables remove when the list is at its minimum" do
    render_inline(described_class.new(min_reached: true))

    expect(page).to have_css("[data-remove-item][disabled]")
  end

  it "renders contextual workspace icon actions with tooltips and initial move and duplication boundaries" do
    render_inline(described_class.new(workspace: true, first: true, last: true, max_reached: true, number: 2, title: 'Court'))
    expect(page).to have_css("[data-action='click->website-builder#moveItemUp'][disabled][aria-label='Move up item 2: Court'][title='#{I18n.t('website.admin.pages.index.move_up')}']")
    expect(page).to have_css("[data-action='click->website-builder#moveItemDown'][disabled][title='#{I18n.t('website.admin.pages.index.move_down')}']")
    expect(page).to have_css("[data-duplicate-item][disabled][title='#{I18n.t('website.admin.pages.edit.duplicate_item')}']")
    expect(page).to have_css("[data-remove-item]:not([disabled])[title='#{I18n.t('common.actions.remove')}']")
    buttons = page.all('button', visible: :all)
    expect(buttons.map { |button| button.text(:all).strip }).to all(be_empty)
    expect(buttons.map { |button| button[:class].split }).to all(include('size-8', 'focus-visible:ring-2'))
  end

  it "floats into the item header only in a wide workspace panel" do
    render_inline(described_class.new(workspace: true))
    expect(page.find('div')[:class].split).to include('@min-[21rem]/content:absolute', '@min-[21rem]/content:right-2')

    render_inline(described_class.new)
    expect(page.find('div')[:class]).not_to include('absolute')
  end

  it "fades in on item hover or focus only where it floats in a wide workspace header" do
    render_inline(described_class.new(workspace: true))
    expect(page.find('div')[:class].split).to include('@min-[21rem]/content:pointer-fine:opacity-0', 'group-hover/item:opacity-100', 'group-focus-within/item:opacity-100')
    expect(page.find('div')[:class].split).not_to include('opacity-0')

    render_inline(described_class.new)
    expect(page.find('div')[:class]).not_to include('opacity')
  end
end
