# Extensible User Architecture

## Overview

This document describes the professional approach for making the `User` model extensible, allowing entity-specific types to inherit base user attributes and add their own custom attributes.

## Architecture Design

### Core Concepts

1. **Base User Model** - Contains core user attributes (first_name, last_name, email, gender)
2. **User Profiles** - Polymorphic association linking Users to entity-specific data
3. **Entity Integration** - Leverage existing Entity/EntityEntry system for dynamic attributes
4. **Type-Safe Extensions** - Specific profile models for different user types

### Design Pattern: Composition over Inheritance

Instead of using Single Table Inheritance (STI), we use **composition** with polymorphic associations:

```
┌─────────────────┐
│      User       │  Base model with core attributes
│  (Core Model)   │  - first_name, last_name
│                 │  - email, gender
│                 │  - customer_id, status
└────────┬────────┘
         │
         │ has_one :profile (polymorphic)
         │
    ┌────┴──────────────────────────────┐
    │                                    │
┌───▼──────────┐              ┌─────────▼────────┐
│   Employee   │              │  ClientProfile   │
│   Profile    │              │                  │
├──────────────┤              ├──────────────────┤
│ - position   │              │ - company_name   │
│ - department │              │ - industry       │
│ - salary     │              │ - website        │
│ - hire_date  │              │ - tax_id         │
└──────────────┘              └──────────────────┘
```

### Database Schema

```ruby
# users table (existing)
create_table :users do |t|
  t.string :first_name
  t.string :last_name
  t.string :email
  t.string :gender
  t.references :customer
  t.integer :status

  # Polymorphic association
  t.string :profile_type
  t.bigint :profile_id

  t.timestamps
end

add_index :users, [:profile_type, :profile_id]

# employee_profiles table (example)
create_table :employee_profiles do |t|
  t.string :position
  t.string :department
  t.decimal :salary
  t.date :hire_date
  t.string :employee_id

  t.timestamps
end

# client_profiles table (example)
create_table :client_profiles do |t|
  t.string :company_name
  t.string :industry
  t.string :website
  t.string :tax_id
  t.text :notes

  t.timestamps
end
```

## Implementation Components

### 1. Enhanced User Model

```ruby
class User < ApplicationRecord
  # Polymorphic association to profile
  belongs_to :profile, polymorphic: true, optional: true

  # Delegation to profile
  delegate :type_name, to: :profile, allow_nil: true

  # Factory method for creating typed users
  def self.create_with_profile(user_attrs, profile_type, profile_attrs)
    User.transaction do
      profile = profile_type.constantize.create!(profile_attrs)
      create!(user_attrs.merge(profile: profile))
    end
  end

  # Check if user has a specific profile type
  def has_profile_type?(type)
    profile_type == type.to_s
  end

  # Get typed profile
  def typed_profile
    profile
  end
end
```

### 2. Profile Models (Examples)

```ruby
# app/models/employee_profile.rb
class EmployeeProfile < ApplicationRecord
  has_one :user, as: :profile, dependent: :destroy

  validates :position, presence: true
  validates :department, presence: true
  validates :employee_id, uniqueness: true

  def type_name
    'Employee'
  end

  def full_profile_data
    attributes.merge(user&.attributes || {})
  end
end

# app/models/client_profile.rb
class ClientProfile < ApplicationRecord
  has_one :user, as: :profile, dependent: :destroy

  validates :company_name, presence: true

  def type_name
    'Client'
  end

  def full_profile_data
    attributes.merge(user&.attributes || {})
  end
end
```

### 3. ExtendableUser Concern

```ruby
# app/models/concerns/extendable_user.rb
module ExtendableUser
  extend ActiveSupport::Concern

  included do
    has_one :user, as: :profile, dependent: :destroy

    delegate :first_name, :last_name, :email, :gender, :full_name,
             to: :user, allow_nil: true
  end

  class_methods do
    def create_with_user(user_attrs, profile_attrs)
      transaction do
        profile = new(profile_attrs)
        profile.user = User.create!(user_attrs)
        profile.save!
        profile
      end
    end
  end

  def full_profile_data
    user_data = user&.attributes&.except('profile_type', 'profile_id') || {}
    profile_data = attributes
    user_data.merge(profile_data)
  end
end
```

### 4. User Factory Service

```ruby
# app/services/user_factory.rb
class UserFactory
  PROFILE_TYPES = {
    employee: 'EmployeeProfile',
    client: 'ClientProfile'
  }.freeze

  def self.create(type, user_attrs, profile_attrs, customer:)
    profile_class = PROFILE_TYPES[type.to_sym]
    raise ArgumentError, "Unknown profile type: #{type}" unless profile_class

    User.transaction do
      profile = profile_class.constantize.create!(profile_attrs)
      User.create!(
        user_attrs.merge(
          profile: profile,
          customer: customer
        )
      )
    end
  end

  def self.update_with_profile(user, user_attrs, profile_attrs)
    User.transaction do
      user.update!(user_attrs) if user_attrs.present?
      user.profile&.update!(profile_attrs) if profile_attrs.present?
      user
    end
  end
end
```

### 5. Contract Pattern

```ruby
# app/contracts/employee_user_contract.rb
class EmployeeUserContract < Reform::Form
  # User attributes
  property :first_name
  property :last_name
  property :email
  property :gender

  # Employee profile attributes
  property :position
  property :department
  property :salary
  property :hire_date
  property :employee_id

  # Validations
  validates :first_name, :last_name, :email, presence: true
  validates :position, :department, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end
```

### 6. Controller Pattern

```ruby
# app/controllers/employees_controller.rb
class EmployeesController < ApplicationController
  def create
    user_attrs = employee_params.slice(:first_name, :last_name, :email, :gender)
    profile_attrs = employee_params.slice(:position, :department, :salary, :hire_date, :employee_id)

    @user = UserFactory.create(:employee, user_attrs, profile_attrs, customer: current_customer)

    if @user.persisted?
      redirect_to employees_path, notice: 'Employee created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @user = current_customer.users.find(params[:id])

    user_attrs = employee_params.slice(:first_name, :last_name, :email, :gender)
    profile_attrs = employee_params.slice(:position, :department, :salary, :hire_date)

    UserFactory.update_with_profile(@user, user_attrs, profile_attrs)
    redirect_to employee_path(@user), notice: 'Employee updated successfully'
  end
end
```

## Benefits

### 1. **Separation of Concerns**
- Core user attributes separate from type-specific data
- Easy to add new user types without modifying base User model

### 2. **Type Safety**
- Each profile type has its own model and validations
- No null columns for attributes that don't apply to all types

### 3. **Flexibility**
- Easy to add new user types by creating new profile models
- Existing users can change profile types if needed

### 4. **Maintainability**
- Clear structure and responsibilities
- Easy to test each component independently

### 5. **Integration with Existing System**
- Can still use Entity/EntityEntry for truly dynamic attributes
- Profiles can have `has_many :entity_entries` for additional flexibility

## Alternative Approach: Entity-Based Extension

For even more flexibility, profiles can be linked to Entities:

```ruby
class EmployeeProfile < ApplicationRecord
  include ExtendableUser

  belongs_to :entity, optional: true
  has_many :entity_entries, through: :entity

  def dynamic_attributes
    return {} unless entity

    entity_entries.each_with_object({}) do |entry, hash|
      hash[entry.attribute_name] = entry.value
    end
  end
end
```

This allows:
1. Static attributes defined in profile model
2. Dynamic attributes from Entity/EntityEntry system
3. Best of both worlds: type safety + flexibility

## Migration Path

### Phase 1: Add Polymorphic Association
```ruby
add_column :users, :profile_type, :string
add_column :users, :profile_id, :bigint
add_index :users, [:profile_type, :profile_id]
```

### Phase 2: Create Profile Models
- Create profile tables
- Create profile models with ExtendableUser concern

### Phase 3: Migrate Existing Users (Optional)
```ruby
# Create default profiles for existing users
User.where(profile_id: nil).find_each do |user|
  profile = BasicUserProfile.create!
  user.update!(profile: profile)
end
```

## Usage Examples

### Creating an Employee
```ruby
employee_user = UserFactory.create(
  :employee,
  { first_name: 'John', last_name: 'Doe', email: 'john@example.com', gender: 'male' },
  { position: 'Senior Developer', department: 'Engineering', salary: 120000 },
  customer: current_customer
)

employee_user.first_name      # => "John"
employee_user.profile.position # => "Senior Developer"
employee_user.profile.type_name # => "Employee"
```

### Creating a Client
```ruby
client_user = UserFactory.create(
  :client,
  { first_name: 'Jane', last_name: 'Smith', email: 'jane@company.com' },
  { company_name: 'Acme Corp', industry: 'Technology', tax_id: '123456789' },
  customer: current_customer
)

client_user.profile.company_name # => "Acme Corp"
client_user.profile.type_name     # => "Client"
```

### Querying by Profile Type
```ruby
# All employees
employees = User.where(profile_type: 'EmployeeProfile')

# All clients
clients = User.where(profile_type: 'ClientProfile')

# Users without profiles
basic_users = User.where(profile_id: nil)
```

## Conclusion

This architecture provides a professional, scalable approach to extending the User model while maintaining:
- Clean code organization
- Type safety
- Flexibility for future extensions
- Integration with existing systems
- Easy testing and maintenance
