require 'redis'
require_relative '../crypto/secp256r1'

module Storage
  # Wrapper for a public key string that provides verifier interface
  class VerificationKey
    def initialize(public_key_string)
      @public_key = public_key_string
      @verifier_instance = Crypto::Secp256r1Verifier.new
    end

    def public
      @public_key
    end

    def verifier
      @verifier_instance
    end
  end

  class VerificationKeyStore
    def initialize(redis_client)
      @redis = redis_client
    end

    def get(identity)
      key = @redis.get(identity)
      raise "Key not found for identity: #{identity}" unless key

      VerificationKey.new(key)
    end
  end
end
