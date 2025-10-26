require 'redis'
require 'json'
require 'time'
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
    HSM_PUBLIC_KEY = '1AAIAjIhd42fcH957TzvXeMbgX4AftiTT7lKmkJ7yHy3dph9'

    def initialize(redis_client)
      @redis = redis_client
      @verifier = Crypto::Secp256r1Verifier.new
    end

    def get(identity)
      value = @redis.get(identity)
      raise "Key not found for identity: #{identity}" unless value

      # Extract the raw body JSON substring without re-encoding
      body_start = value.index('"body":')
      raise "missing body in HSM response" unless body_start

      body_start += '"body":'.length

      brace_count = 0
      in_body = false
      body_end = nil

      value[body_start..-1].each_char.with_index do |char, i|
        idx = body_start + i
        case char
        when '{'
          in_body = true
          brace_count += 1
        when '}'
          brace_count -= 1
          if in_body && brace_count == 0
            body_end = idx + 1
            break
          end
        end
      end

      raise "failed to extract body from HSM response" unless body_end

      body_json = value[body_start...body_end]

      # Parse the full response to get signature
      hsm_response = JSON.parse(value)
      signature = hsm_response['signature']
      raise "missing signature in HSM response" unless signature

      # Parse body to validate contents
      body = JSON.parse(body_json)

      # Verify HSM identity
      raise "invalid HSM identity" unless body['hsmIdentity'] == HSM_PUBLIC_KEY

      # Verify the signature over the raw body JSON
      # Convert string to byte array to match better-auth library convention
      @verifier.verify(signature, HSM_PUBLIC_KEY, body_json.bytes)

      # Validate purpose
      payload = body['payload'] || {}
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
  end
end
