require 'redis'
require 'json'
require 'time'
require_relative '../crypto/secp256r1'
require_relative 'key_verifier'
require_relative 'utils'

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
    def initialize(redis_client, redis_host, redis_db_hsm_keys, server_lifetime_hours, access_lifetime_minutes)
      @redis = redis_client
      @key_verifier = KeyVerifier.new(redis_host, redis_db_hsm_keys, server_lifetime_hours, access_lifetime_minutes)
      @verifier = Crypto::Secp256r1Verifier.new
    end

    def get(identity)
      value = @redis.get(identity)
      raise "Key not found for identity: #{identity}" unless value

      # Parse the response structure
      response_obj = JSON.parse(value)

      # Extract raw body JSON for signature verification
      body_json = get_sub_json(value, 'body')

      # Verify HSM signature using KeyVerifier
      @key_verifier.verify(
        response_obj['signature'],
        response_obj['body']['hsm']['identity'],
        response_obj['body']['hsm']['generationId'],
        body_json
      )

      # Validate purpose
      payload = response_obj['body']['payload'] || {}
      purpose = payload['purpose']
      raise "invalid purpose: expected access, got #{purpose}" unless purpose == 'access'

      # Check expiration
      expiration_str = payload['expiration']
      if expiration_str
        expiration = Time.parse(expiration_str)
        raise "key expired" if expiration <= Time.now
      end

      # Return the public key from the payload
      public_key = payload['publicKey']
      raise "missing publicKey in payload" unless public_key

      VerificationKey.new(public_key)
    end

    def close
      @key_verifier.close
    end
  end
end
