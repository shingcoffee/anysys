# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EntityAttributeAudience do
  describe '.applying_audiences' do
    it 'returns every audience when visibility and validator_apply are missing' do
      expect(described_class.applying_audiences('validators' => [{ 'type' => 'presence' }]))
        .to eq(%w[admin member public])
    end

    it 'excludes audiences that are not visible' do
      attr = {
        'visibility' => { 'admin' => true, 'member' => true, 'public' => false },
        'validator_apply' => { 'admin' => true, 'member' => true, 'public' => true }
      }
      expect(described_class.applying_audiences(attr)).to eq(%w[admin member])
    end

    it 'excludes audiences with validator_apply false' do
      attr = { 'validator_apply' => { 'admin' => false, 'member' => false, 'public' => true } }
      expect(described_class.applying_audiences(attr)).to eq(%w[public])
    end

    it 'intersects visibility with validator_apply' do
      attr = {
        'visibility' => { 'admin' => true, 'member' => false, 'public' => true },
        'validator_apply' => { 'admin' => true, 'member' => true, 'public' => false }
      }
      expect(described_class.applying_audiences(attr)).to eq(%w[admin])
    end

    it 'accepts symbol-keyed flag maps' do
      attr = { validator_apply: { admin: false, member: true, public: true } }
      expect(described_class.applying_audiences(attr)).to eq(%w[member public])
    end

    it 'returns an empty list when no audience applies' do
      attr = { 'validator_apply' => { 'admin' => false, 'member' => false, 'public' => false } }
      expect(described_class.applying_audiences(attr)).to be_empty
    end

    it 'ignores non-hash schema entries and non-hash flag maps' do
      expect(described_class.applying_audiences('nope')).to eq(%w[admin member public])
      expect(described_class.applying_audiences('visibility' => 'yes')).to eq(%w[admin member public])
    end

    it 'skips audiences that see the field but cannot edit it' do
      attr = { 'editable' => { 'admin' => true, 'member' => false, 'public' => false } }
      expect(described_class.applying_audiences(attr)).to eq(%w[admin])
    end
  end

  describe '.editable_by?' do
    let(:attr) do
      { 'visibility' => { 'admin' => true, 'member' => true, 'public' => false },
        'editable' => { 'admin' => true, 'member' => false, 'public' => true } }
    end

    it 'needs the audience to see the field and be allowed to change it' do
      expect(described_class.editable_by?(attr, 'admin')).to be true
      expect(described_class.editable_by?(attr, :member)).to be false
      expect(described_class.editable_by?(attr, 'public')).to be false
    end

    it 'is editable by every audience that sees it when no editable map is declared' do
      expect(described_class.editable_by?({ 'name_slug' => 'x' }, 'member')).to be true
    end

    it 'is editable for a blank audience (unscoped run)' do
      expect(described_class.editable_by?(attr, nil)).to be true
    end
  end

  describe '.visible_to?' do
    let(:attr) { { 'visibility' => { 'admin' => true, 'member' => false, 'public' => false } } }

    it 'follows the visibility map' do
      expect(described_class.visible_to?(attr, 'admin')).to be true
      expect(described_class.visible_to?(attr, :member)).to be false
      expect(described_class.visible_to?(attr, 'public')).to be false
    end

    it 'is visible for a blank audience (unscoped run)' do
      expect(described_class.visible_to?(attr, nil)).to be true
      expect(described_class.visible_to?(attr, '')).to be true
    end

    it 'is visible when no visibility map is declared' do
      expect(described_class.visible_to?({ 'name_slug' => 'x' }, 'public')).to be true
    end

    it 'ignores validator_apply, which only gates validators' do
      entry = { 'validator_apply' => { 'public' => false } }
      expect(described_class.visible_to?(entry, 'public')).to be true
    end
  end

  describe '.every_audience?' do
    it 'is true only for the full audience list' do
      expect(described_class.every_audience?(%w[admin member public])).to be true
      expect(described_class.every_audience?(%w[admin member])).to be false
    end
  end

  describe '.for_user' do
    let(:customer_id) { 12345678 }

    def viewer(role, customer_id: 12345678)
      double(primary_role_key: role, customer_id: customer_id, platform_owner?: false)
    end

    it 'maps anonymous visitors to public' do
      expect(described_class.for_user(nil, customer_id: customer_id)).to eq('public')
    end

    it 'maps same-tenant owners and admins to admin' do
      expect(described_class.for_user(viewer('owner'), customer_id: customer_id)).to eq('admin')
      expect(described_class.for_user(viewer('admin'), customer_id: customer_id)).to eq('admin')
    end

    it 'maps same-tenant members to member' do
      expect(described_class.for_user(viewer('member'), customer_id: customer_id)).to eq('member')
    end

    it 'falls back to public for unrecognised roles' do
      expect(described_class.for_user(viewer('robot'), customer_id: customer_id)).to eq('public')
    end

    it 'does not grant a foreign admin or member their home-tenant audience' do
      %w[admin member owner].each do |role|
        expect(described_class.for_user(viewer(role, customer_id: 87654321), customer_id: customer_id)).to eq('public')
      end
    end

    it 'requires an identified tenant before granting a role audience' do
      expect(described_class.for_user(viewer('admin'), customer_id: nil)).to eq('public')
    end

    it 'honors the fixed platform owner exception across tenants' do
      owner = find_or_create_platform_owner
      expect(described_class.for_user(owner, customer_id: customer_id)).to eq('admin')
    end

    it 'uses an explicit tenant instead of ambient Current for standalone rendering' do
      Current.set(customer: nil) do
        expect(described_class.for_user(viewer('admin'), customer_id: customer_id.to_s)).to eq('admin')
        expect(described_class.for_user(viewer('admin'))).to eq('public')
      end
    end
  end

  describe '.contract_guard' do
    def host_class(audience)
      Class.new do
        include EntityAttributeAudience::ContractScope
        self.default_validation_audience = audience
      end
    end

    it 'resolves the audience through the instance class' do
      guard = described_class.contract_guard(%w[public])

      expect(host_class(nil).new.instance_exec(&guard)).to be true # unscoped run
      expect(host_class('admin').new.instance_exec(&guard)).to be false
      expect(host_class('public').new.instance_exec(&guard)).to be true
    end

    it 'survives being forwarded through a SimpleDelegator, as reform-rails does' do
      guard = described_class.contract_guard(%w[public])
      delegator = SimpleDelegator.new(host_class('admin').new)

      expect(delegator.instance_exec(&guard)).to be false
    end

    it 'snapshots the audience list so later caller mutation cannot widen it' do
      audiences = %w[public]
      guard = described_class.contract_guard(audiences)
      audiences << 'admin'

      expect(host_class('admin').new.instance_exec(&guard)).to be false
    end
  end

  describe '.contract_guard_source' do
    it 'emits Ruby that mirrors the runtime guard' do
      expect(described_class.contract_guard_source(%w[admin public]))
        .to eq('if: -> { validators_apply_to_audience?(["admin", "public"]) }')
    end
  end

  describe EntityAttributeAudience::ContractScope do
    let(:host) do
      Class.new do
        include EntityAttributeAudience::ContractScope
        self.default_validation_audience = 'member'
      end
    end

    it 'exposes the class-level audience' do
      expect(host.validation_audience).to eq('member')
    end

    it 'applies validators only for the matching audience' do
      expect(host.validators_apply_to_audience?(%w[member public])).to be true
      expect(host.validators_apply_to_audience?(%w[admin])).to be false
    end

    it 'delegates the instance predicate to the class' do
      expect(host.new.validators_apply_to_audience?(%w[member])).to be true
      expect(host.new.validators_apply_to_audience?(%w[admin])).to be false
    end

    it 'defaults to an unscoped audience that applies everything' do
      unscoped = Class.new { include EntityAttributeAudience::ContractScope }

      expect(unscoped.validation_audience).to be_nil
      expect(unscoped.validators_apply_to_audience?([])).to be true
    end
  end
end
