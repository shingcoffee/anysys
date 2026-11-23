# Quick Start Example - Employee Extension for Users

This guide shows you exactly how to use the generic extensibility pattern to create an Employee extension for Users.

## Step-by-Step Example

### Step 1: The User Model is Already Extensible

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include SoftDeletable
  include TenantScoped
  include Extendable  # ← This line makes User extensible (already done!)

  belongs_to :customer
  # ... rest of User model
end
```

That's it! No changes needed to the `users` table. The User model can now be extended.

### Step 2: Create an Employee Entity (One-time setup in Rails console)

```ruby
# In Rails console or seeds
customer = Customer.find(1)  # or Customer.first

employee_entity = Entity.create!(
  name: 'Employee',
  name_slug: 'employee',
  customer: customer,
  property_schema: [
    {
      name: 'Position',
      name_slug: 'position',
      type: 'String',
      validators: ['presence']
    },
    {
      name: 'Department',
      name_slug: 'department',
      type: 'String',
      validators: ['presence']
    },
    {
      name: 'Salary',
      name_slug: 'salary',
      type: 'Float',
      validators: ['numericality']
    },
    {
      name: 'Hire Date',
      name_slug: 'hire_date',
      type: 'String',
      validators: []
    },
    {
      name: 'Employee ID',
      name_slug: 'employee_id',
      type: 'String',
      validators: ['presence']
    }
  ].to_json
)

puts "✅ Employee entity created with ID: #{employee_entity.id}"
```

### Step 3: Create Users with Employee Extension

```ruby
# Method 1: Using ExtendedModelService (Recommended)
employee = ExtendedModelService.create(
  User,
  {
    first_name: 'John',
    last_name: 'Doe',
    email: 'john.doe@company.com',
    gender: 'male'
  },
  'Employee',
  {
    position: 'Senior Software Engineer',
    department: 'Engineering',
    salary: 120000.00,
    hire_date: '2024-01-15',
    employee_id: 'EMP001'
  },
  customer: customer
)

puts "✅ Created employee: #{employee.full_name}"

# Method 2: Using model method
employee2 = User.create_with_extension(
  {
    first_name: 'Jane',
    last_name: 'Smith',
    email: 'jane.smith@company.com',
    gender: 'female',
    customer: customer
  },
  'Employee',
  {
    position: 'Product Manager',
    department: 'Product',
    salary: 110000.00,
    hire_date: '2024-02-01',
    employee_id: 'EMP002'
  }
)

puts "✅ Created employee: #{employee2.full_name}"

# Create a few more for testing
ExtendedModelService.create(User,
  { first_name: 'Alice', last_name: 'Johnson', email: 'alice@company.com', gender: 'female' },
  'Employee',
  { position: 'Senior Developer', department: 'Engineering', salary: 115000, hire_date: '2024-01-20', employee_id: 'EMP003' },
  customer: customer)

ExtendedModelService.create(User,
  { first_name: 'Bob', last_name: 'Williams', email: 'bob@company.com', gender: 'male' },
  'Employee',
  { position: 'Junior Developer', department: 'Engineering', salary: 80000, hire_date: '2024-03-01', employee_id: 'EMP004' },
  customer: customer)

ExtendedModelService.create(User,
  { first_name: 'Carol', last_name: 'Davis', email: 'carol@company.com', gender: 'female' },
  'Employee',
  { position: 'Designer', department: 'Design', salary: 95000, hire_date: '2024-02-15', employee_id: 'EMP005' },
  customer: customer)

puts "✅ Created 5 employees total"
```

### Step 4: Access Extension Data

```ruby
# Get extension data
employee_data = employee.extension_data('Employee')
puts employee_data
# => {
#   "position" => "Senior Software Engineer",
#   "department" => "Engineering",
#   "salary" => 120000.0,
#   "hire_date" => "2024-01-15",
#   "employee_id" => "EMP001"
# }

# Access specific fields
puts "Position: #{employee_data['position']}"
puts "Department: #{employee_data['department']}"
puts "Salary: $#{employee_data['salary']}"

# Check if user has extension
puts employee.has_extension?('Employee')  # => true

# Get all extension names
puts employee.extension_names  # => ["Employee"]

# Get merged attributes (base + extension)
full_attrs = employee.full_attributes('Employee')
puts full_attrs
# => {
#   "first_name" => "John",
#   "last_name" => "Doe",
#   "email" => "john.doe@company.com",
#   "gender" => "male",
#   "position" => "Senior Software Engineer",
#   "department" => "Engineering",
#   "salary" => 120000.0,
#   ...
# }
```

### Step 5: Query Employees

```ruby
# Find all employees
all_employees = User.of_extension_type('Employee')
puts "Total employees: #{all_employees.count}"

# Find employees by department (simple)
engineers = User.where_extension('Employee', 'department', 'Engineering')
puts "Engineers: #{engineers.count}"

# Complex queries using Query Builder
senior_engineers = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .where_extension('Employee', 'department', 'Engineering')
  .where_extension('Employee', 'position', 'Senior Software Engineer')
  .where(status: 'active')
  .with_extensions
  .order(:created_at, :desc)
  .all

puts "Senior Engineers: #{senior_engineers.count}"

# Get all employees in Engineering with eager loading
engineers_with_data = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .where_extension('Employee', 'department', 'Engineering')
  .with_extensions  # Eager load extension data
  .order(:created_at, :desc)
  .all

engineers_with_data.each do |eng|
  data = eng.extension_data('Employee')
  puts "#{eng.full_name} - #{data['position']}"
end

# Count employees by department
engineering_count = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .where_extension('Employee', 'department', 'Engineering')
  .count

puts "Engineering dept size: #{engineering_count}"

# Paginated results
page_1 = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .paginate(1, 10)  # Page 1, 10 per page
  .all

puts "Page 1 employees: #{page_1.count}"
```

### Step 6: Update Extension Data

```ruby
# Update extension data only
employee.set_extension_data('Employee', {
  position: 'Lead Software Engineer',
  department: 'Engineering',
  salary: 150000.00,
  hire_date: '2024-01-15',
  employee_id: 'EMP001'
})

puts "✅ Updated #{employee.full_name}'s extension data"

# Update both base and extension
ExtendedModelService.update(
  employee,
  { first_name: 'John' },  # Base attributes
  {
    'Employee' => {         # Extension attributes
      position: 'Staff Engineer',
      salary: 180000.00,
      department: 'Engineering',
      hire_date: '2024-01-15',
      employee_id: 'EMP001'
    }
  }
)

puts "✅ Updated both base and extension data"
```

### Step 7: Get Extension Statistics

```ruby
# Get stats on extension usage
stats = ExtendedModelService.extension_stats(User, customer: customer)
puts stats
# => { "Employee" => 5 }

# Get all extension types for User model
extension_types = ExtendedModelService.extension_types(User, customer: customer)
puts "Extension types: #{extension_types.pluck(:name)}"
# => ["Employee"]

# Find users without any extensions
regular_users = ExtendedModelService.without_extensions(User, customer: customer)
puts "Regular users (no extensions): #{regular_users.count}"
```

### Step 8: Remove Extension

```ruby
# Create a temporary employee for demo
temp_employee = User.create_with_extension(
  { first_name: 'Temp', last_name: 'Worker', email: 'temp@company.com', customer: customer },
  'Employee',
  { position: 'Contractor', department: 'General', salary: 50000, employee_id: 'TMP001', hire_date: '2024-01-01' }
)

puts "Created: #{temp_employee.full_name} with Employee extension"
puts "Has extension? #{temp_employee.has_extension?('Employee')}"  # => true

# Remove the extension
temp_employee.remove_extension('Employee')

puts "Removed extension"
puts "Has extension? #{temp_employee.has_extension?('Employee')}"  # => false

# User record still exists, but extension is gone
puts "User still exists: #{temp_employee.persisted?}"  # => true
```

## Real-World Controller Example

```ruby
# app/controllers/employees_controller.rb
class EmployeesController < ApplicationController
  set_tenant_from_route_params required: true
  before_action :require_admin_role!
  before_action :set_employee, only: [:show, :edit, :update, :destroy]

  def index
    @employees = ExtendedModelQueryBuilder.new(User, customer: current_customer)
      .of_type('Employee')
      .with_extensions
      .order(:created_at, :desc)

    # Apply filters
    if params[:department].present?
      @employees = @employees.where_extension('Employee', 'department', params[:department])
    end

    if params[:position].present?
      @employees = @employees.where_extension('Employee', 'position', params[:position])
    end

    @employees = @employees.all
    @stats = ExtendedModelService.extension_stats(User, customer: current_customer)
  end

  def show
    @employee_data = @employee.extension_data('Employee')
  end

  def create
    base_attrs = user_params.merge(customer: current_customer)
    extension_attrs = employee_params

    @employee = ExtendedModelService.create(
      User,
      base_attrs,
      'Employee',
      extension_attrs,
      customer: current_customer
    )

    if @employee.persisted?
      redirect_to employees_path, notice: "Employee #{@employee.full_name} created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    ExtendedModelService.update(
      @employee,
      user_params,
      { 'Employee' => employee_params }
    )

    redirect_to employee_path(@employee), notice: 'Employee updated successfully'
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  private

  def set_employee
    @employee = User.of_extension_type('Employee').find(params[:id])
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :gender, :status)
  end

  def employee_params
    params.require(:employee).permit(:position, :department, :salary, :hire_date, :employee_id)
  end
end
```

## View Examples

```erb
<%# app/views/employees/index.html.erb %>
<div class="container mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold mb-6">Employees</h1>

  <%# Extension Stats %>
  <div class="mb-6">
    <%= extension_stats_summary(User, current_customer) %>
  </div>

  <%# Employees Table %>
  <table class="min-w-full">
    <thead>
      <tr>
        <th>Name</th>
        <th>Email</th>
        <th>Position</th>
        <th>Department</th>
        <th>Salary</th>
      </tr>
    </thead>
    <tbody>
      <% @employees.each do |employee| %>
        <% employee_data = employee.extension_data('Employee') %>
        <tr>
          <td><%= employee.full_name %></td>
          <td><%= employee.email %></td>
          <td><%= employee_data['position'] %></td>
          <td><%= employee_data['department'] %></td>
          <td><%= number_to_currency(employee_data['salary']) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

```erb
<%# app/views/employees/show.html.erb %>
<div class="max-w-4xl mx-auto px-4 py-8">
  <h1 class="text-2xl font-bold mb-6"><%= @employee.full_name %></h1>

  <%# Extension Badges %>
  <%= extension_badges(@employee, class: 'mb-4') %>

  <%# Base Attributes %>
  <div class="bg-white p-6 rounded-lg shadow mb-6">
    <h2 class="text-lg font-semibold mb-4">Basic Information</h2>
    <dl class="grid grid-cols-2 gap-4">
      <div>
        <dt class="text-sm font-medium text-gray-500">Email</dt>
        <dd class="text-sm text-gray-900"><%= @employee.email %></dd>
      </div>
      <div>
        <dt class="text-sm font-medium text-gray-500">Gender</dt>
        <dd class="text-sm text-gray-900"><%= @employee.gender&.titleize %></dd>
      </div>
    </dl>
  </div>

  <%# Extension Attributes %>
  <div class="bg-white p-6 rounded-lg shadow">
    <h2 class="text-lg font-semibold mb-4">Employee Details</h2>
    <%= render_extension_attributes(@employee, 'Employee') %>
  </div>
</div>
```

## Testing

```ruby
# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  let(:customer) { create(:customer) }
  let(:employee_entity) { create(:entity, name: 'Employee', customer: customer) }

  describe 'with Employee extension' do
    it 'creates user with extension data' do
      user = User.create_with_extension(
        { first_name: 'John', last_name: 'Doe', email: 'john@example.com', customer: customer },
        employee_entity,
        { position: 'Developer', department: 'Engineering' }
      )

      expect(user).to be_persisted
      expect(user.has_extension?(employee_entity)).to be true
      expect(user.extension_data(employee_entity)['position']).to eq('Developer')
    end

    it 'queries by extension attribute' do
      3.times do |i|
        User.create_with_extension(
          { first_name: "User#{i}", last_name: 'Test', email: "user#{i}@example.com", customer: customer },
          employee_entity,
          { position: 'Developer', department: i.even? ? 'Engineering' : 'Product' }
        )
      end

      engineers = User.where_extension(employee_entity, 'department', 'Engineering')
      expect(engineers.count).to eq(2)
    end
  end
end
```

## Summary

With just **one line** (`include Extendable`) in the User model, you can:

1. ✅ Create extension schemas dynamically (Entity)
2. ✅ Attach extensions to users without schema changes
3. ✅ Query users by extension attributes efficiently
4. ✅ Update extension data independently
5. ✅ Remove extensions when needed
6. ✅ Get statistics on extension usage
7. ✅ Use in views with helper methods

The same pattern works for **any model** - Products, Orders, Customers, etc. Just add `include Extendable` and you're done!
