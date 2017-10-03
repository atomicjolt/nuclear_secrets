require "nuclear_secrets/engine"

module NuclearSecrets
  class NuclearSecretError < StandardError
    def initialize(secrets: [])
      @secrets = secrets
    end

    def get_error_list
      @secrets.reduce("") do |message, current|
        message << "#{current.first} of type #{current[1]}"
        message << if current.last.nil?
                     "\n"
                   else
                     "was given #{current.last}\n"
                   end
      end
    end
  end

  class RequiredSecretsListMissing < NuclearSecretError
    def message
      "You must include a NuclearSecrets initializer in your app"
    end
  end

  class SecretsMissingError < NuclearSecretError
    def initialize(secrets)
      super(secrets: secrets)
    end

    def message
      "Missing secrets: \n#{get_error_list}"
    end
  end

  class ExtraSecretsError < NuclearSecretError
    def initialize(secrets)
      super(secrets: secrets)
    end

    def message
      "Secrets not included in required_secrets list: \n#{get_error_list}"
    end
  end

  class InvalidRequiredSecretValue < NuclearSecretError
    def initialize(secrets)
      super(secrets: secrets)
    end

    def message
      "Invalid required secret: \n#{get_error_list}"
    end
  end

  class MismatchedSecretType < NuclearSecretError
    def initialize(secrets)
      super(secrets: secrets)
    end

    def message
      "Invalid secrets given: \n#{get_error_list}"
    end
  end

  class << self
    attr_accessor(:required_secrets)

    def configure
      yield self if block_given?
    end

    def make_type_check(type)
      Proc.new { |item| item.class == type }
    end

    # [key, req, given]
    def build_secret_tuple(secrets, required_values, key)
      [key, required_values[key], secrets[key]]
    end

    def build_pairs(keys, secrets)
      keys.map do |k|
        build_secret_tuple(secrets, required_secrets, k)
      end
    end

    def build_assertions(secrets, existing_keys)
      existing_keys.map do |key|
        if required_secrets[key].class == Class
          make_type_check(required_secrets[key])
        elsif required_secrets[key].respond_to? :call
          required_secrets[key]
        else
          raise NuclearSecrets::InvalidRequiredSecretValue.new(
            [
              build_secret_tuple(secrets, required_secrets, key),
            ],
          )
        end
      end
    end

    def check_assertions(secrets, assertions)
      secrets.to_a.zip(assertions).select do |pair|
        result = pair.last.call(pair.first[1])
        if !result
          pair.first[0]
        else
          false
        end
      end.map { |key| build_pairs(key, secrets) }
    end

    def check_secrets(secrets)
      raise NuclearSecrets::RequiredSecretsListMissing if required_secrets.nil?
      req_keys = required_secrets.keys
      existing_keys = secrets.keys

      missing_keys = req_keys - existing_keys
      extra_keys = existing_keys - req_keys

      missing_pairs = build_pairs(missing_keys, secrets)
      extra_pairs = build_pairs(extra_keys, secrets)
      raise SecretsMissingError.new(missing_pairs) unless missing_keys.empty?
      raise ExtraSecretsError.new(extra_pairs) unless extra_keys.empty?    
      
      assertions = build_assertions(secrets, existing_keys)
      error_pairs = check_assertions(secrets, assertions)
      raise MismatchedSecretType.new(error_pairs) if !error_pairs.empty?

      # TODO print proc in error message
    end
  end
end
