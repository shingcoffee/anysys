# Comprehensive Generators Phase 2 — Security, Concurrency & Service Invocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 new step action generators: 3 security (Authenticate, HashData, GenerateToken) + 1 concurrency (AcquireLock) + 1 service invocation (InvokeService). Also update SourceAssembler::CATEGORIES with 2 new categories.

**Architecture:** Each generator follows the existing BaseGenerator pattern. Security generators extend the existing security category. Concurrency and service_invocation are new category directories. All generators are independently testable and auto-discovered by GeneratorRegistry.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec

---

## File Structure

| File | Purpose |
|------|---------|
| `app/services/code_generators/source_assembler.rb` | Add `:concurrency` and `:service_invocation` to CATEGORIES |
| `app/services/code_generators/element_types/process/security/authenticate_generator.rb` | Authenticate users via password/token/api_key/jwt |
| `app/services/code_generators/element_types/process/security/hash_data_generator.rb` | Hash data using SHA256/SHA512/MD5/bcrypt |
| `app/services/code_generators/element_types/process/security/generate_token_generator.rb` | Generate tokens (SecureRandom/JWT/HMAC/UUID) |
| `app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb` | Acquire advisory/pessimistic/redis locks |
| `app/services/code_generators/element_types/process/service_invocation/invoke_service_generator.rb` | Invoke arbitrary service classes |
| `spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb` | Authenticate tests |
| `spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb` | HashData tests |
| `spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb` | GenerateToken tests |
| `spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb` | AcquireLock tests |
| `spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb` | InvokeService tests |

---

### Task 1: Update SourceAssembler CATEGORIES

**Files:**
- Modify: `app/services/code_generators/source_assembler.rb`

- [ ] **Step 1: Add new categories to CATEGORIES array**

Edit line 5-8 in `app/services/code_generators/source_assembler.rb` to change:

```ruby
CATEGORIES = %i[
  flow_control model_operations validation data_operations
  communication security background file_operations realtime response
].freeze
```

to:

```ruby
CATEGORIES = %i[
  flow_control model_operations validation data_operations
  communication security background file_operations realtime response
  concurrency service_invocation
].freeze
```

- [ ] **Step 2: Run existing SourceAssembler specs to verify no regression**

Run: `bundle exec rspec spec/services/code_generators/ --format documentation`
Expected: All existing tests pass

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/source_assembler.rb
git commit -m "$(cat <<'EOF'
chore: update source_assembler categories

Add :concurrency and :service_invocation to SourceAssembler::CATEGORIES
to support new generator categories in Phase 2.
EOF
)"
```

---

### Task 2: Authenticate generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/security/authenticate_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::AuthenticateGenerator do
  let(:element) { { "config" => { "authMethod" => "password", "sourceVariable" => "credentials", "userVariable" => "user", "targetVariable" => "authenticated_user" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "password authentication" do
    it "generates password auth code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:authenticated_user] = ctx[:user]&.authenticate(ctx[:credentials])")
      expect(code).to include("Railway.fail!")
      expect(code).to include("true")
    end

    it "uses raise when failAction is raise" do
      el = { "config" => { "authMethod" => "password", "sourceVariable" => "credentials", "userVariable" => "user", "targetVariable" => "result", "failAction" => "raise" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('raise "Authentication failed"')
      expect(code).not_to include("Railway.fail!")
    end
  end

  describe "token authentication" do
    it "generates bearer token extraction" do
      el = { "config" => { "authMethod" => "token", "sourceVariable" => "auth_header", "tokenType" => "bearer", "targetVariable" => "token" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('ctx[:token] = ctx[:auth_header].to_s.sub(/\ABearer\s+/i, "")')
      expect(code).to include("true")
    end

    it "generates basic token extraction" do
      el = { "config" => { "authMethod" => "token", "sourceVariable" => "auth_header", "tokenType" => "basic", "targetVariable" => "decoded" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('ctx[:auth_header].to_s.sub(/\ABasic\s+/i, "")')
    end

    it "generates custom token passthrough" do
      el = { "config" => { "authMethod" => "token", "sourceVariable" => "raw_token", "tokenType" => "custom", "targetVariable" => "token" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:token] = ctx[:raw_token]")
    end
  end

  describe "api_key authentication" do
    it "generates api key comparison" do
      el = { "config" => { "authMethod" => "api_key", "sourceVariable" => "provided_key", "expectedKeyVariable" => "stored_key", "targetVariable" => "key_valid" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ActiveSupport::SecurityUtils.secure_compare(ctx[:provided_key].to_s, ctx[:stored_key].to_s)")
      expect(code).to include("Railway.fail!")
      expect(code).to include("ctx[:key_valid] = true")
    end
  end

  describe "jwt authentication" do
    it "generates JWT decode" do
      el = { "config" => { "authMethod" => "jwt", "sourceVariable" => "jwt_token", "secretVariable" => "jwt_secret", "targetVariable" => "claims", "algorithm" => "HS256" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('JWT.decode(ctx[:jwt_token], ctx[:jwt_secret], true, algorithm: "HS256").first')
      expect(code).to include("ctx[:claims]")
    end

    it "defaults algorithm to HS256" do
      el = { "config" => { "authMethod" => "jwt", "sourceVariable" => "token", "secretVariable" => "secret", "targetVariable" => "payload" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('algorithm: "HS256"')
    end
  end

  describe "default auth method" do
    it "defaults to password when authMethod not set" do
      el = { "config" => { "sourceVariable" => "creds", "userVariable" => "user", "targetVariable" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("authenticate(ctx[:creds])")
    end
  end

  describe "validation" do
    it "requires authMethod and sourceVariable" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({})
      expect(errors).to include("authMethod is required")
      expect(errors).to include("sourceVariable is required")
    end

    it "requires secretVariable for jwt" do
      errors = described_class.new(element, {}).validate_config({ "authMethod" => "jwt", "sourceVariable" => "token" })
      expect(errors).to include("secretVariable is required for jwt authentication")
    end

    it "accepts valid config" do
      errors = described_class.new(element, {}).validate_config({ "authMethod" => "password", "sourceVariable" => "creds" })
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/security/authenticate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class AuthenticateGenerator < BaseGenerator
          AUTH_METHODS = %w[password token api_key jwt].freeze

          generator_metadata do
            description "Authenticates users via password, token, API key, or JWT"
            category :security
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            auth_method = config["authMethod"] || "password"
            source = config["sourceVariable"] || "credentials"
            target = config["targetVariable"] || "result"
            fail_action = config["failAction"] || "fail_track"

            case auth_method
            when "password"   then generate_password(source, target, fail_action)
            when "token"      then generate_token(source, target)
            when "api_key"    then generate_api_key(source, target, fail_action)
            when "jwt"        then generate_jwt(source, target)
            else generate_password(source, target, fail_action)
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "authMethod is required" if cfg["authMethod"].blank?
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            if cfg["authMethod"] == "jwt" && cfg["secretVariable"].blank?
              errors << "secretVariable is required for jwt authentication"
            end
            errors
          end

          def example_output
            <<~RUBY.chomp
              ctx[:authenticated_user] = ctx[:user]&.authenticate(ctx[:credentials])
              unless ctx[:authenticated_user]
                Railway.fail!
              end
              true
            RUBY
          end

          private

          def generate_password(source, target, fail_action)
            user_var = config["userVariable"] || "user"
            fail_line = fail_action == "raise" ? 'raise "Authentication failed"' : "Railway.fail!"
            <<~RUBY.chomp
              ctx[:#{target}] = ctx[:#{user_var}]&.authenticate(ctx[:#{source}])
              unless ctx[:#{target}]
                #{fail_line}
              end
              true
            RUBY
          end

          def generate_token(source, target)
            token_type = config["tokenType"] || "bearer"
            case token_type
            when "bearer"
              "ctx[:#{target}] = ctx[:#{source}].to_s.sub(/\\ABearer\\s+/i, \"\")\ntrue"
            when "basic"
              "ctx[:#{target}] = ctx[:#{source}].to_s.sub(/\\ABasic\\s+/i, \"\")\ntrue"
            when "custom"
              "ctx[:#{target}] = ctx[:#{source}]\ntrue"
            else
              "ctx[:#{target}] = ctx[:#{source}].to_s.sub(/\\ABearer\\s+/i, \"\")\ntrue"
            end
          end

          def generate_api_key(source, target, fail_action)
            expected_var = config["expectedKeyVariable"] || "expected_key"
            fail_line = fail_action == "raise" ? 'raise "Authentication failed"' : "Railway.fail!"
            <<~RUBY.chomp
              unless ActiveSupport::SecurityUtils.secure_compare(ctx[:#{source}].to_s, ctx[:#{expected_var}].to_s)
                #{fail_line}
              end
              ctx[:#{target}] = true
              true
            RUBY
          end

          def generate_jwt(source, target)
            secret_var = config["secretVariable"] || "jwt_secret"
            algorithm = config["algorithm"] || "HS256"
            "ctx[:#{target}] = JWT.decode(ctx[:#{source}], ctx[:#{secret_var}], true, algorithm: #{algorithm.inspect}).first\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/security/authenticate_generator.rb spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add Authenticate generator

Supports password, token (bearer/basic/custom), api_key, and jwt
authentication methods with configurable fail actions.
EOF
)"
```

---

### Task 3: HashData generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/security/hash_data_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::HashDataGenerator do
  let(:element) { { "config" => { "sourceVariable" => "password", "targetVariable" => "hashed", "algorithm" => "sha256" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "SHA256 hashing" do
    it "generates SHA256 hexdigest" do
      code = described_class.new(element, context).generate
      expect(code).to include("Digest::SHA256.hexdigest(ctx[:password].to_s)")
      expect(code).to include("ctx[:hashed]")
      expect(code).to include("true")
    end

    it "generates SHA256 with salt" do
      el = { "config" => { "sourceVariable" => "password", "targetVariable" => "hashed", "algorithm" => "sha256", "saltVariable" => "salt" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Digest::SHA256.hexdigest(ctx[:salt] + ctx[:password].to_s)")
    end
  end

  describe "SHA512 hashing" do
    it "generates SHA512 hexdigest" do
      el = { "config" => { "sourceVariable" => "data", "targetVariable" => "hash", "algorithm" => "sha512" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Digest::SHA512.hexdigest(ctx[:data].to_s)")
      expect(code).to include("ctx[:hash]")
    end
  end

  describe "MD5 hashing" do
    it "generates MD5 hexdigest" do
      el = { "config" => { "sourceVariable" => "content", "targetVariable" => "checksum", "algorithm" => "md5" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Digest::MD5.hexdigest(ctx[:content].to_s)")
      expect(code).to include("ctx[:checksum]")
    end
  end

  describe "bcrypt hashing" do
    it "generates bcrypt with default cost" do
      el = { "config" => { "sourceVariable" => "password", "targetVariable" => "digest", "algorithm" => "bcrypt" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("BCrypt::Password.create(ctx[:password], cost: 12)")
      expect(code).to include("ctx[:digest]")
    end

    it "generates bcrypt with custom cost" do
      el = { "config" => { "sourceVariable" => "password", "targetVariable" => "digest", "algorithm" => "bcrypt", "cost" => 10 } }
      code = described_class.new(el, {}).generate
      expect(code).to include("cost: 10")
    end
  end

  describe "default algorithm" do
    it "defaults to sha256" do
      el = { "config" => { "sourceVariable" => "data", "targetVariable" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Digest::SHA256")
    end
  end

  describe "validation" do
    it "requires sourceVariable" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({})
      expect(errors).to include("sourceVariable is required")
    end

    it "validates algorithm if present" do
      errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "data", "algorithm" => "ripemd" })
      expect(errors).to include(/Invalid algorithm/)
    end

    it "accepts valid config" do
      errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "data", "algorithm" => "sha256" })
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/security/hash_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class HashDataGenerator < BaseGenerator
          ALGORITHMS = %w[sha256 sha512 md5 bcrypt].freeze

          generator_metadata do
            description "Hashes data using SHA256, SHA512, MD5, or bcrypt"
            category :security
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "data"
            target = config["targetVariable"] || "hashed"
            algorithm = config["algorithm"] || "sha256"
            salt_var = config["saltVariable"]

            case algorithm
            when "sha256" then generate_digest("SHA256", source, target, salt_var)
            when "sha512" then generate_digest("SHA512", source, target, salt_var)
            when "md5"    then generate_digest("MD5", source, target, salt_var)
            when "bcrypt" then generate_bcrypt(source, target)
            else generate_digest("SHA256", source, target, salt_var)
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            if cfg["algorithm"].present? && !ALGORITHMS.include?(cfg["algorithm"])
              errors << "Invalid algorithm: #{cfg['algorithm']}. Must be one of: #{ALGORITHMS.join(', ')}"
            end
            errors
          end

          def example_output
            "ctx[:hashed] = Digest::SHA256.hexdigest(ctx[:password].to_s)\ntrue"
          end

          private

          def generate_digest(digest_class, source, target, salt_var)
            if salt_var.present?
              "ctx[:#{target}] = Digest::#{digest_class}.hexdigest(ctx[:#{salt_var}] + ctx[:#{source}].to_s)\ntrue"
            else
              "ctx[:#{target}] = Digest::#{digest_class}.hexdigest(ctx[:#{source}].to_s)\ntrue"
            end
          end

          def generate_bcrypt(source, target)
            cost = config["cost"] || 12
            "ctx[:#{target}] = BCrypt::Password.create(ctx[:#{source}], cost: #{cost})\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/security/hash_data_generator.rb spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add HashData generator

Supports SHA256, SHA512, MD5, and bcrypt hashing with optional salt
for digest algorithms and configurable cost for bcrypt.
EOF
)"
```

---

### Task 4: GenerateToken generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/security/generate_token_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::GenerateTokenGenerator do
  let(:element) { { "config" => { "tokenType" => "secure_random", "targetVariable" => "token", "length" => 32 } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "secure_random token" do
    it "generates SecureRandom.hex with specified length" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:token] = SecureRandom.hex(32)")
      expect(code).to include("true")
    end

    it "defaults length to 32" do
      el = { "config" => { "tokenType" => "secure_random", "targetVariable" => "token" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("SecureRandom.hex(32)")
    end
  end

  describe "jwt token" do
    it "generates JWT encode without expiry" do
      el = { "config" => { "tokenType" => "jwt", "targetVariable" => "jwt", "payloadVariable" => "claims", "secretVariable" => "secret" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('JWT.encode(ctx[:claims], ctx[:secret], "HS256")')
      expect(code).to include("ctx[:jwt]")
      expect(code).not_to include("exp:")
    end

    it "generates JWT encode with expiry" do
      el = { "config" => { "tokenType" => "jwt", "targetVariable" => "jwt", "payloadVariable" => "claims", "secretVariable" => "secret", "expiresIn" => 3600 } }
      code = described_class.new(el, {}).generate
      expect(code).to include("_payload = ctx[:claims].merge(exp: Time.current.to_i + 3600)")
      expect(code).to include('JWT.encode(_payload, ctx[:secret], "HS256")')
    end

    it "supports custom algorithm" do
      el = { "config" => { "tokenType" => "jwt", "targetVariable" => "jwt", "payloadVariable" => "claims", "secretVariable" => "secret", "algorithm" => "HS512" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('"HS512"')
    end
  end

  describe "hmac token" do
    it "generates HMAC hexdigest" do
      el = { "config" => { "tokenType" => "hmac", "targetVariable" => "signature", "dataVariable" => "message", "secretVariable" => "key" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('OpenSSL::HMAC.hexdigest("SHA256", ctx[:key], ctx[:message])')
      expect(code).to include("ctx[:signature]")
    end

    it "supports sha512 digest" do
      el = { "config" => { "tokenType" => "hmac", "targetVariable" => "sig", "dataVariable" => "data", "secretVariable" => "key", "digest" => "sha512" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('"SHA512"')
    end
  end

  describe "uuid token" do
    it "generates SecureRandom.uuid" do
      el = { "config" => { "tokenType" => "uuid", "targetVariable" => "id" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:id] = SecureRandom.uuid")
      expect(code).to include("true")
    end
  end

  describe "validation" do
    it "requires targetVariable" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({})
      expect(errors).to include("targetVariable is required")
    end

    it "requires payloadVariable and secretVariable for jwt" do
      errors = described_class.new(element, {}).validate_config({ "targetVariable" => "tok", "tokenType" => "jwt" })
      expect(errors).to include("payloadVariable is required for jwt token generation")
      expect(errors).to include("secretVariable is required for jwt token generation")
    end

    it "requires dataVariable and secretVariable for hmac" do
      errors = described_class.new(element, {}).validate_config({ "targetVariable" => "sig", "tokenType" => "hmac" })
      expect(errors).to include("dataVariable is required for hmac token generation")
      expect(errors).to include("secretVariable is required for hmac token generation")
    end

    it "accepts valid secure_random config" do
      errors = described_class.new(element, {}).validate_config({ "targetVariable" => "tok", "tokenType" => "secure_random" })
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/security/generate_token_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class GenerateTokenGenerator < BaseGenerator
          TOKEN_TYPES = %w[secure_random jwt hmac uuid].freeze

          generator_metadata do
            description "Generates tokens (SecureRandom, JWT, HMAC, UUID)"
            category :security
            version "1.0.0"
          end

          input_schema  # dynamic — varies by token type
          output_schema :target_variable

          def generate
            token_type = config["tokenType"] || "secure_random"
            target = config["targetVariable"] || "token"

            case token_type
            when "secure_random" then generate_secure_random(target)
            when "jwt"           then generate_jwt(target)
            when "hmac"          then generate_hmac(target)
            when "uuid"          then generate_uuid(target)
            else generate_secure_random(target)
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "targetVariable is required" if cfg["targetVariable"].blank?

            case cfg["tokenType"]
            when "jwt"
              errors << "payloadVariable is required for jwt token generation" if cfg["payloadVariable"].blank?
              errors << "secretVariable is required for jwt token generation" if cfg["secretVariable"].blank?
            when "hmac"
              errors << "dataVariable is required for hmac token generation" if cfg["dataVariable"].blank?
              errors << "secretVariable is required for hmac token generation" if cfg["secretVariable"].blank?
            end

            errors
          end

          def example_output
            "ctx[:token] = SecureRandom.hex(32)\ntrue"
          end

          private

          def generate_secure_random(target)
            length = config["length"] || 32
            "ctx[:#{target}] = SecureRandom.hex(#{length})\ntrue"
          end

          def generate_jwt(target)
            payload_var = config["payloadVariable"] || "payload"
            secret_var = config["secretVariable"] || "secret"
            algorithm = config["algorithm"] || "HS256"
            expires_in = config["expiresIn"]

            if expires_in.present? && expires_in.to_i > 0
              <<~RUBY.chomp
                _payload = ctx[:#{payload_var}].merge(exp: Time.current.to_i + #{expires_in.to_i})
                ctx[:#{target}] = JWT.encode(_payload, ctx[:#{secret_var}], #{algorithm.inspect})
                true
              RUBY
            else
              "ctx[:#{target}] = JWT.encode(ctx[:#{payload_var}], ctx[:#{secret_var}], #{algorithm.inspect})\ntrue"
            end
          end

          def generate_hmac(target)
            data_var = config["dataVariable"] || "data"
            secret_var = config["secretVariable"] || "secret"
            digest = (config["digest"] || "sha256").upcase
            "ctx[:#{target}] = OpenSSL::HMAC.hexdigest(#{digest.inspect}, ctx[:#{secret_var}], ctx[:#{data_var}])\ntrue"
          end

          def generate_uuid(target)
            "ctx[:#{target}] = SecureRandom.uuid\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/security/generate_token_generator.rb spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add GenerateToken generator

Supports secure_random, JWT, HMAC, and UUID token generation with
configurable parameters including expiry, algorithm, and digest.
EOF
)"
```

---

### Task 5: AcquireLock generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Concurrency::AcquireLockGenerator do
  let(:element) { { "config" => { "lockType" => "advisory", "lockKey" => "order_processing", "timeout" => 5 } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "advisory lock" do
    it "generates advisory lock with static key" do
      code = described_class.new(element, context).generate
      expect(code).to include('Zlib.crc32("order_processing")')
      expect(code).to include("pg_try_advisory_lock")
      expect(code).to include("Railway.fail!")
      expect(code).to include("ctx[:_advisory_lock_id] = _lock_id")
      expect(code).to include("true")
    end

    it "generates advisory lock with dynamic key variable" do
      el = { "config" => { "lockType" => "advisory", "lockKeyVariable" => "resource_id" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Zlib.crc32(ctx[:resource_id].to_s)")
    end

    it "uses raise when failAction is raise" do
      el = { "config" => { "lockType" => "advisory", "lockKey" => "test", "failAction" => "raise" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('raise "Failed to acquire lock"')
      expect(code).not_to include("Railway.fail!")
    end
  end

  describe "pessimistic lock" do
    it "generates lock! with reload" do
      el = { "config" => { "lockType" => "pessimistic", "modelVariable" => "order" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:order] = ctx[:order].lock!")
      expect(code).to include("ctx[:order].reload")
      expect(code).to include("true")
    end

    it "skips reload when reloadAfterLock is false" do
      el = { "config" => { "lockType" => "pessimistic", "modelVariable" => "order", "reloadAfterLock" => false } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:order] = ctx[:order].lock!")
      expect(code).not_to include("reload")
    end
  end

  describe "redis lock" do
    it "generates redis lock with defaults" do
      el = { "config" => { "lockType" => "redis", "lockKey" => "worker_lock" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('_lock_key = "worker_lock"')
      expect(code).to include("Redis.current.set(_lock_key, SecureRandom.hex, nx: true, ex: 30)")
      expect(code).to include("3.times do")
      expect(code).to include("sleep 0.2")
      expect(code).to include("Railway.fail!")
      expect(code).to include("ctx[:_redis_lock_key] = _lock_key")
    end

    it "generates redis lock with custom ttl and retry" do
      el = { "config" => { "lockType" => "redis", "lockKey" => "custom", "ttl" => 60, "retryCount" => 5, "retryDelay" => 0.5 } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ex: 60")
      expect(code).to include("5.times do")
      expect(code).to include("sleep 0.5")
    end

    it "generates redis lock with dynamic key variable" do
      el = { "config" => { "lockType" => "redis", "lockKeyVariable" => "job_id" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:job_id].to_s")
    end
  end

  describe "validation" do
    it "requires lockType" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({})
      expect(errors).to include("lockType is required")
    end

    it "requires lockKey or lockKeyVariable for advisory" do
      errors = described_class.new(element, {}).validate_config({ "lockType" => "advisory" })
      expect(errors).to include("lockKey or lockKeyVariable is required for advisory lock")
    end

    it "requires modelVariable for pessimistic" do
      errors = described_class.new(element, {}).validate_config({ "lockType" => "pessimistic" })
      expect(errors).to include("modelVariable is required for pessimistic lock")
    end

    it "requires lockKey or lockKeyVariable for redis" do
      errors = described_class.new(element, {}).validate_config({ "lockType" => "redis" })
      expect(errors).to include("lockKey or lockKeyVariable is required for redis lock")
    end

    it "accepts valid advisory config" do
      errors = described_class.new(element, {}).validate_config({ "lockType" => "advisory", "lockKey" => "test" })
      expect(errors).to be_empty
    end

    it "accepts valid pessimistic config" do
      errors = described_class.new(element, {}).validate_config({ "lockType" => "pessimistic", "modelVariable" => "order" })
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Concurrency
        class AcquireLockGenerator < BaseGenerator
          LOCK_TYPES = %w[advisory pessimistic redis].freeze

          generator_metadata do
            description "Acquires database advisory, pessimistic, or Redis distributed locks"
            category :concurrency
            version "1.0.0"
          end

          input_schema  # dynamic — varies by lock type
          output_schema :target_variable

          def generate
            lock_type = config["lockType"] || "advisory"
            fail_action = config["failAction"] || "fail_track"

            case lock_type
            when "advisory"    then generate_advisory(fail_action)
            when "pessimistic" then generate_pessimistic
            when "redis"       then generate_redis(fail_action)
            else generate_advisory(fail_action)
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "lockType is required" if cfg["lockType"].blank?

            case cfg["lockType"]
            when "advisory"
              if cfg["lockKey"].blank? && cfg["lockKeyVariable"].blank?
                errors << "lockKey or lockKeyVariable is required for advisory lock"
              end
            when "pessimistic"
              errors << "modelVariable is required for pessimistic lock" if cfg["modelVariable"].blank?
            when "redis"
              if cfg["lockKey"].blank? && cfg["lockKeyVariable"].blank?
                errors << "lockKey or lockKeyVariable is required for redis lock"
              end
            end

            errors
          end

          def example_output
            <<~RUBY.chomp
              _lock_id = Zlib.crc32("order_processing")
              _acquired = ActiveRecord::Base.connection.execute("SELECT pg_try_advisory_lock(\#{_lock_id})").first["pg_try_advisory_lock"]
              unless _acquired
                Railway.fail!
              end
              ctx[:_advisory_lock_id] = _lock_id
              true
            RUBY
          end

          private

          def generate_advisory(fail_action)
            key_expr = if config["lockKeyVariable"].present?
                         "Zlib.crc32(ctx[:#{config['lockKeyVariable']}].to_s)"
                       else
                         key = config["lockKey"] || "default_lock"
                         "Zlib.crc32(#{key.inspect})"
                       end
            fail_line = fail_action == "raise" ? 'raise "Failed to acquire lock"' : "Railway.fail!"

            <<~RUBY.chomp
              _lock_id = #{key_expr}
              _acquired = ActiveRecord::Base.connection.execute("SELECT pg_try_advisory_lock(\#{_lock_id})").first["pg_try_advisory_lock"]
              unless _acquired
                #{fail_line}
              end
              ctx[:_advisory_lock_id] = _lock_id
              true
            RUBY
          end

          def generate_pessimistic
            model_var = config["modelVariable"] || "model"
            reload = config.fetch("reloadAfterLock", true)

            lines = []
            lines << "ctx[:#{model_var}] = ctx[:#{model_var}].lock!"
            lines << "ctx[:#{model_var}].reload" if reload != false
            lines << "true"
            lines.join("\n")
          end

          def generate_redis(fail_action)
            key_expr = if config["lockKeyVariable"].present?
                         "ctx[:#{config['lockKeyVariable']}].to_s"
                       else
                         key = config["lockKey"] || "default_lock"
                         key.inspect
                       end
            ttl = config["ttl"] || 30
            retry_count = config["retryCount"] || 3
            retry_delay = config["retryDelay"] || 0.2
            fail_line = fail_action == "raise" ? 'raise "Failed to acquire lock"' : "Railway.fail!"

            <<~RUBY.chomp
              _lock_key = #{key_expr}
              _acquired = false
              #{retry_count}.times do
                _acquired = Redis.current.set(_lock_key, SecureRandom.hex, nx: true, ex: #{ttl})
                break if _acquired
                sleep #{retry_delay}
              end
              unless _acquired
                #{fail_line}
              end
              ctx[:_redis_lock_key] = _lock_key
              true
            RUBY
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add AcquireLock generator

Supports PostgreSQL advisory locks, ActiveRecord pessimistic locks,
and Redis distributed locks with configurable retry and TTL.
EOF
)"
```

---

### Task 6: InvokeService generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/service_invocation/invoke_service_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ServiceInvocation::InvokeServiceGenerator do
  let(:element) { { "config" => { "serviceClass" => "OrderService", "targetVariable" => "result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "simple class method call" do
    it "generates class method .call with no args" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:result] = OrderService.call")
      expect(code).to include("true")
    end
  end

  describe "with positional arguments" do
    it "generates call with positional args" do
      el = { "config" => { "serviceClass" => "NotificationService", "targetVariable" => "sent", "arguments" => [{ "name" => "user", "sourceVariable" => "current_user" }, { "name" => "message", "sourceVariable" => "msg" }] } }
      code = described_class.new(el, {}).generate
      expect(code).to include("NotificationService.call(ctx[:current_user], ctx[:msg])")
      expect(code).to include("ctx[:sent]")
    end
  end

  describe "with keyword arguments" do
    it "generates call with keyword args" do
      el = { "config" => { "serviceClass" => "PaymentProcessor", "targetVariable" => "charge", "keywordArguments" => { "amount" => "total", "currency" => "currency_code" } } }
      code = described_class.new(el, {}).generate
      expect(code).to include("PaymentProcessor.call(amount: ctx[:total], currency: ctx[:currency_code])")
      expect(code).to include("ctx[:charge]")
    end
  end

  describe "with both positional and keyword arguments" do
    it "generates call with mixed args" do
      el = { "config" => { "serviceClass" => "ReportGenerator", "targetVariable" => "report", "arguments" => [{ "name" => "data", "sourceVariable" => "dataset" }], "keywordArguments" => { "format" => "fmt" } } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ReportGenerator.call(ctx[:dataset], format: ctx[:fmt])")
    end
  end

  describe "custom method (instance method)" do
    it "generates instance method call" do
      el = { "config" => { "serviceClass" => "PdfGenerator", "callMethod" => "render", "targetVariable" => "pdf", "arguments" => [{ "name" => "template", "sourceVariable" => "tpl" }] } }
      code = described_class.new(el, {}).generate
      expect(code).to include("PdfGenerator.new.render(ctx[:tpl])")
      expect(code).to include("ctx[:pdf]")
    end

    it "generates instance method call with no args" do
      el = { "config" => { "serviceClass" => "HealthCheck", "callMethod" => "run", "targetVariable" => "status" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("HealthCheck.new.run")
      expect(code).to include("ctx[:status]")
    end
  end

  describe "default call method" do
    it "defaults to .call class method" do
      el = { "config" => { "serviceClass" => "MyService", "targetVariable" => "out" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("MyService.call")
      expect(code).not_to include(".new.")
    end
  end

  describe "validation" do
    it "requires serviceClass and targetVariable" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({})
      expect(errors).to include("serviceClass is required")
      expect(errors).to include("targetVariable is required")
    end

    it "accepts valid config" do
      errors = described_class.new(element, {}).validate_config({ "serviceClass" => "MyService", "targetVariable" => "result" })
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/service_invocation/invoke_service_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ServiceInvocation
        class InvokeServiceGenerator < BaseGenerator
          generator_metadata do
            description "Invokes an arbitrary service class with positional and/or keyword arguments"
            category :service_invocation
            version "1.0.0"
          end

          input_schema  # dynamic — varies by arguments
          output_schema :target_variable

          def generate
            service_class = config["serviceClass"] || "ApplicationService"
            call_method = config["callMethod"] || "call"
            target = config["targetVariable"] || "result"

            args_str = build_arguments_string

            invocation = if call_method == "call"
                           "#{service_class}.call#{args_str.empty? ? '' : "(#{args_str})"}"
                         else
                           "#{service_class}.new.#{call_method}#{args_str.empty? ? '' : "(#{args_str})"}"
                         end

            "ctx[:#{target}] = #{invocation}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "serviceClass is required" if cfg["serviceClass"].blank?
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            errors
          end

          def example_output
            "ctx[:result] = OrderService.call(ctx[:order_id])\ntrue"
          end

          private

          def build_arguments_string
            positional = build_positional_args
            keyword = build_keyword_args

            parts = []
            parts << positional if positional.present?
            parts << keyword if keyword.present?
            parts.join(", ")
          end

          def build_positional_args
            args = config["arguments"]
            return "" unless args.is_a?(Array) && args.any?

            args.map { |arg| "ctx[:#{arg['sourceVariable']}]" }.join(", ")
          end

          def build_keyword_args
            kwargs = config["keywordArguments"]
            return "" unless kwargs.is_a?(Hash) && kwargs.any?

            kwargs.map { |param, source_var| "#{param}: ctx[:#{source_var}]" }.join(", ")
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/service_invocation/invoke_service_generator.rb spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add InvokeService generator

Supports class method (.call) and instance method invocation with
positional arguments, keyword arguments, or both.
EOF
)"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run all new generator specs together**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb spec/services/code_generators/element_types/process/security/hash_data_generator_spec.rb spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb spec/services/code_generators/element_types/process/service_invocation/invoke_service_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 2: Run all security generator specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/security/ --format documentation`
Expected: All pass (existing authorize + encrypt_data + 3 new)

- [ ] **Step 3: Verify generators are auto-discovered by registry**

Run: `bundle exec rails runner "puts CodeGenerators::GeneratorRegistry.instance.step_action_generators.keys.sort.join(', ')"`
Expected: Output includes `authenticate`, `hash_data`, `generate_token`, `acquire_lock`, `invoke_service` among the existing generator names

- [ ] **Step 4: Run full test suite**

Run: `bundle exec rspec --format documentation`
Expected: All pass, no regressions

- [ ] **Step 5: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: verify all Phase 2 generators registered and passing

5 new generators (Authenticate, HashData, GenerateToken, AcquireLock,
InvokeService) and 2 new categories (concurrency, service_invocation)
fully integrated.
EOF
)"
```
