# frozen_string_literal: true

class Customer < ApplicationRecord
  include SoftDeletable
  include RandomIdGeneratable

  # ==========================================================================
  # Configuration
  # ==========================================================================

  soft_deletable deleted_status: :inactive
  random_id digits: 8

  # ==========================================================================
  # Enums
  # ==========================================================================

  enum :status, { active: 0, inactive: 1 }, default: :active, validate: true
  enum :tier, { basic: 0, standard: 1, premium: 2, enterprise: 3 }, default: :basic, validate: true
  enum :role, { owner: 0, admin: 1, member: 2 }, default: :owner, validate: true
  # Industry taxonomy (enum integers + select groupings) is defined once in
  # config/industries.yml and loaded here; see INDUSTRY_GROUPS below.
  INDUSTRY_TAXONOMY = YAML.load_file(Rails.root.join("config/industries.yml")).freeze

  enum :industry,
       INDUSTRY_TAXONOMY.flat_map { |g| g["industries"].to_a }.to_h.transform_keys(&:to_sym),
       validate: true

  # ==========================================================================
  # Callbacks
  # ==========================================================================

  after_create :seed_reserved_roles_for_self
  after_create :enable_required_feature_modules
  after_create_commit :run_billing_onboarding
  before_destroy :purge_owned_records, prepend: true

  # When true, Authentication::Provisioner is not run from after_create so a
  # public customer sign-up can attach the real admin as the first user.
  attr_accessor :skip_authentication_provisioner

  # ==========================================================================
  # Associations (Tenant-scoped resources)
  # ==========================================================================

  has_many :roles, dependent: :destroy
  has_many :flowcharts, dependent: :destroy
  has_many :entities, dependent: :destroy
  has_many :entity_entries, dependent: :destroy
  has_many :entity_domains, dependent: :destroy
  has_many :customer_feature_modules, dependent: :destroy,
                                      class_name: "FeatureModules::CustomerAssignment",
                                      foreign_key: :customer_id
  has_many :feature_modules, through: :customer_feature_modules
  has_many :users, class_name: "Authentication::User", dependent: :destroy

  # ==========================================================================
  # Validations
  # ==========================================================================

  validates :name, presence: true, length: { maximum: 100 }
  validates :industry, presence: true

  # The platform tenant is the prefix of every platform URL. Soft-deleting it
  # hides the row from Customer.visible, and restore itself lives under that
  # prefix, so the owner can no longer open the tools that would bring it back.
  def soft_delete
    if id == Authentication::User::PLATFORM_CUSTOMER_ID
      errors.add(:base, I18n.t("maint_platform.flash.customers.platform_protected"))
      return false
    end

    super
  end

  # Optional tenant-wide default UI locale (see AddLocaleToCustomers). Blank
  # means "no default". When present it must be a supported locale; blank is
  # normalized to nil so `locale?`/resolution treats "" and nil identically.
  normalizes :locale, with: ->(value) { value.presence }
  # At most one custom domain, stored as a string. Blank means none.
  before_validation :normalize_domain
  validates :locale,
            inclusion: { in: ->(_record) { I18n.available_locales.map(&:to_s) } },
            allow_blank: true
  validate :domain_available
  validate :verify_domain_cname, if: :verify_domain_cname?

  # ==========================================================================
  # Scopes
  # ==========================================================================

  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(query) {
    return all if query.blank?

    tokens = query.to_s.downcase.split(/\s+/).reject(&:blank?)
    return all if tokens.empty?

    tokens.inject(all) do |relation, token|
      pat = "%#{sanitize_sql_like(token)}%"
      if token.match?(/\A\d+\z/)
        relation.where(
          "LOWER(name) LIKE :pat ESCAPE '\\' OR LOWER(\"alias\") LIKE :pat ESCAPE '\\' OR id = :id",
          pat: pat, id: token.to_i
        )
      else
        relation.where(
          "LOWER(name) LIKE :pat ESCAPE '\\' OR LOWER(\"alias\") LIKE :pat ESCAPE '\\'",
          pat: pat
        )
      end
    end
  }

  default_scope { visible }

  INDUSTRY_GROUPS = INDUSTRY_TAXONOMY.to_h { |g| [g["name"], g["industries"].keys.map(&:to_sym)] }.freeze

  def self.grouped_industry_options
    INDUSTRY_GROUPS.map do |group, keys|
      options = keys.map { |k| [industry_label_for(k), k.to_s] }
      [industry_group_label(group), options]
    end
  end

  def self.industry_group_label(name)
    return nil if name.blank?

    I18n.t("customers.industry_groups.#{name.to_s.parameterize(separator: "_")}")
  end

  def self.industry_label_for(key)
    return nil if key.blank?

    I18n.t("customers.industries.#{key}")
  end

  def industry_label
    self.class.industry_label_for(industry)
  end

  def self.domain_owner_id(domain)
    normalized = PageShortcuts::Hosts.normalize(domain.to_s)
    return if normalized.blank?

    uncached { unscoped.where(domain: normalized).pick(:id) }
  end

  private

  def purge_owned_records
    result = Customers::Purge.call(customers: [self], delete_customers: false)
    if result.success?
      self.class.reflect_on_all_associations(:has_many).each { |reflection| association(reflection.name).reset }
      return
    end

    errors.add(:base, :invalid)
    throw :abort
  end

  def normalize_domain
    raw = domain
    if raw.blank?
      self.domain = nil
      return
    end

    normalized = PageShortcuts::Hosts.normalize(raw.to_s)
    if normalized
      self.domain = normalized
    else
      errors.add(:domain, I18n.t("custom_domains.errors.invalid_domain"))
    end
  end

  def domain_available
    return if domain.blank? || errors[:domain].present? || !will_save_change_to_domain?

    owner_id = self.class.domain_owner_id(domain)
    return if owner_id.nil? || owner_id == id

    errors.add(:domain, I18n.t("custom_domains.errors.domain_taken"))
  end

  def verify_domain_cname?
    domain.present? && will_save_change_to_domain? && errors[:domain].blank?
  end

  def verify_domain_cname
    return if CustomDomains::CnameVerifier.call(hostname: domain) == :verified

    errors.add(:domain, I18n.t("custom_domains.errors.cname_unverified"))
  end

  def enable_required_feature_modules
    ::FeatureModules::Module.required.find_each do |fm|
      cfm = customer_feature_modules.find_or_initialize_by(feature_module: fm)
      cfm.update!(status: :active, enabled_at: Time.current, configuration: {}.to_json)
      next if skip_authentication_provisioner && fm.key == "authentication"

      fm.registration_class.provision!(self)
    end
  end

  def run_billing_onboarding
    Billing::Onboarding.call(self)
  end

  def seed_reserved_roles_for_self
    Roles::Operation::SeedReserved.call(customer: self)
  end
end
