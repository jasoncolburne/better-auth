require 'redis'
require 'json'
require 'time'
require_relative '../crypto/secp256r1'
require_relative '../crypto/blake3'
require_relative './utils'

module Storage
  HSM_IDENTITY = 'BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER'

  class LogEntry
    attr_reader :id, :prefix, :previous, :sequence_number, :created_at, :taint_previous, :purpose, :public_key, :rotation_hash

    def initialize(data)
      @id = data['id']
      @prefix = data['prefix']
      @previous = data['previous']
      @sequence_number = data['sequenceNumber']
      @created_at = Time.parse(data['createdAt'])
      @taint_previous = data['taintPrevious']
      @purpose = data['purpose']
      @public_key = data['publicKey']
      @rotation_hash = data['rotationHash']
    end
  end

  class SignedLogEntry
    attr_reader :payload, :signature

    def initialize(data)
      @payload = LogEntry.new(data['payload'])
      @signature = data['signature']
    end
  end

  class KeyVerifier
    def initialize(redis_host, redis_db_hsm_keys, server_lifetime_hours, access_lifetime_minutes)
      @redis = Redis.new(url: "redis://#{redis_host}/#{redis_db_hsm_keys}")
      @verifier = Crypto::Secp256r1Verifier.new
      @hasher = Crypto::Blake3.new
      @cache = {}
      @verification_window = server_lifetime_hours * 3600 + access_lifetime_minutes * 60
    end

    def verify(signature, hsm_identity, hsm_generation_id, message)
      cached_entry = @cache[hsm_generation_id]

      unless cached_entry
        # Clear cache before repopulating
        @cache.clear

        # Fetch all HSM keys from Redis
        keys = @redis.keys('*')
        raise 'No HSM keys found in Redis' if keys.empty?

        values = @redis.mget(*keys)

        # Group by prefix
        by_prefix = {}
        values.compact.each do |value|
          payload_json = get_sub_json(value, 'payload')
          record = SignedLogEntry.new(JSON.parse(value))
          prefix = record.payload.prefix

          by_prefix[prefix] ||= []
          by_prefix[prefix] << [record, payload_json]
        end

        # Sort by sequence number
        by_prefix.each do |prefix, records|
          by_prefix[prefix] = records.sort_by { |r, _| r.payload.sequence_number }
        end

        # Verify data & signatures for all records
        by_prefix.each do |prefix, records|
          records.each do |record, payload_json|
            payload = record.payload

            if payload.sequence_number.zero?
              verify_prefix_and_data(payload_json, payload)
            else
              verify_address_and_data(payload_json, payload)
            end

            # Verify signature over payload
            @verifier.verify(record.signature, payload.public_key, payload_json.bytes)
          end
        end

        # Verify chains
        by_prefix.each_value do |records|
          last_id = ''
          last_rotation_hash = ''

          records.each_with_index do |(record, _), i|
            payload = record.payload

            raise 'bad sequence number' if payload.sequence_number != i

            unless payload.sequence_number.zero?
              raise 'broken chain' if last_id != payload.previous

              hash = @hasher.sum(payload.public_key.bytes)

              raise 'bad commitment' if hash != last_rotation_hash
            end

            last_id = payload.id
            last_rotation_hash = payload.rotation_hash
          end
        end

        # Verify prefix exists
        raise 'hsm identity not found' unless by_prefix.key?(HSM_IDENTITY)

        records = by_prefix[HSM_IDENTITY]

        # Cache entries within 12-hour window (iterate backwards)
        tainted = false
        records.reverse_each do |record, _|
          payload = record.payload
          @cache[payload.id] = payload unless tainted

          tainted = payload.taint_previous || false

          break if payload.created_at + @verification_window < Time.now
        end

        cached_entry = @cache[hsm_generation_id]
        raise "can't find valid public key" unless cached_entry
      end

      raise 'incorrect identity (expected hsm.identity == prefix)' if cached_entry.prefix != hsm_identity
      raise 'incorrect purpose (expected key-authorization)' if cached_entry.purpose != 'key-authorization'

      # Verify message signature
      @verifier.verify(signature, cached_entry.public_key, message.bytes)
    end

    private

    def verify_prefix_and_data(payload_json, payload)
      raise 'prefix must equal id for sequence 0' if payload.id != payload.prefix

      verify_address_and_data(payload_json, payload)
    end

    def verify_address_and_data(payload_json, payload)
      # Serialize payload and replace id with placeholder
      modified_payload = payload_json.gsub(payload.id, '############################################')

      hash = @hasher.sum(modified_payload.bytes)

      raise 'id does not match hash of payload' if hash != payload.id
    end

    def close
      @redis.quit
    end
  end
end
