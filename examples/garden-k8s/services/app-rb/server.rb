require 'sinatra'
require 'redis'
require 'json'
require 'net/http'
require 'uri'
require 'base64'
require 'better_auth'
require 'better_auth/api/access'
require 'better_auth/messages/common'

require_relative 'lib/crypto/secp256r1'
require_relative 'lib/storage/verification_key_store'
require_relative 'lib/storage/timelock'
require_relative 'lib/app_encoding/rfc3339'
require_relative 'lib/app_encoding/token_encoder'

class TokenAttributes
  attr_accessor :permissions_by_role

  def initialize(permissions_by_role = {})
    @permissions_by_role = permissions_by_role
  end

  def to_json(*)
    { permissionsByRole: @permissions_by_role }.to_json(*)
  end

  def self.from_hash(data)
    new(data[:permissionsByRole] || data['permissionsByRole'] || {})
  end
end

class ResponsePayload
  attr_accessor :was_foo, :was_bar, :server_name

  def initialize(was_foo:, was_bar:, server_name:)
    @was_foo = was_foo
    @was_bar = was_bar
    @server_name = server_name
  end

  def to_h
    { wasFoo: @was_foo, wasBar: @was_bar, serverName: @server_name }
  end

  def to_json(*)
    to_h.to_json(*)
  end
end

class ApplicationServer < Sinatra::Base
  configure do
    set :port, 80
    set :bind, '0.0.0.0'
    set :show_exceptions, false

    # Redis configuration
    redis_host = ENV['REDIS_HOST'] || 'redis:6379'
    host, port = redis_host.split(':')
    redis_db_access_keys = (ENV['REDIS_DB_ACCESS_KEYS'] || '0').to_i
    redis_db_response_keys = (ENV['REDIS_DB_RESPONSE_KEYS'] || '1').to_i
    redis_db_revoked_devices = (ENV['REDIS_DB_REVOKED_DEVICES'] || '3').to_i
    redis_db_hsm_keys = (ENV['REDIS_DB_HSM_KEYS'] || '4').to_i

    server_lifetime_hours = 12
    access_lifetime_minutes = 15

    puts "#{Time.now}: Connecting to Redis at #{redis_host}"

    # Connect to Redis DB 0 to read access keys
    access_client = Redis.new(host: host, port: port.to_i, db: redis_db_access_keys)

    # Connect to Redis DB 3 to check revoked devices
    revoked_devices_client = Redis.new(host: host, port: port.to_i, db: redis_db_revoked_devices)

    # Connect to Redis DB 1 to write/read response keys
    response_client = Redis.new(host: host, port: port.to_i, db: redis_db_response_keys)

    begin
      # Create verification key store
      verifier = Crypto::Secp256r1Verifier.new
      verification_key_store = Storage::VerificationKeyStore.new(
        access_client, redis_host, redis_db_hsm_keys, server_lifetime_hours, access_lifetime_minutes
      )

      # Create an in-memory nonce store with 30 second window (in seconds)
      access_nonce_store = Storage::InMemoryTimeLockStore.new(30)

      # Create AccessVerifier
      access_verifier = BetterAuth::API::AccessVerifier.new(
        crypto: BetterAuth::API::VerifierCryptoContainer.new(verifier: verifier),
        encoding: BetterAuth::API::VerifierEncodingContainer.new(
          token_encoder: AppEncoding::TokenEncoder.new,
          timestamper: AppEncoding::Rfc3339.new
        ),
        store: BetterAuth::API::VerifierStoreContainer.new(
          access_nonce: access_nonce_store,
          access_key_store: verification_key_store
        )
      )

      set :verifier, access_verifier
      puts "#{Time.now}: AccessVerifier initialized"

      # Generate app response key
      app_response_key = Crypto::Secp256r1.new
      app_response_public_key = app_response_key.public

      # Sign response key with HSM
      hsm_host = ENV['HSM_HOST'] || 'hsm'
      hsm_port = ENV['HSM_PORT'] || '11111'
      hsm_url = "http://#{hsm_host}:#{hsm_port}"

      ttl = 12 * 60 * 60 + 60 # 12 hours + 1 minute in seconds
      response_expiration = (Time.now + ttl).utc.iso8601(3)
      response_payload = {
        purpose: 'response',
        publicKey: app_response_public_key,
        expiration: response_expiration
      }

      authorization = nil
      begin
        uri = URI("#{hsm_url}/sign")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = {
          payload: response_payload
        }.to_json

        response = http.request(request)
        if response.is_a?(Net::HTTPSuccess)
          authorization = response.body.chomp
          puts "#{Time.now}: Response key HSM authorization: #{authorization}"
        else
          puts "#{Time.now}: Warning: Failed to sign response key with HSM: #{response.code}"
        end
      rescue => e
        puts "#{Time.now}: Warning: Failed to contact HSM: #{e.message}"
      end

      # Store the full HSM authorization in Redis DB 1 with 12 hour 1 minute TTL
      if authorization
        response_client.set(app_response_public_key, authorization, ex: ttl)
        puts "#{Time.now}: Registered app response key in Redis DB 1 (TTL: 12 hours): #{app_response_public_key[0..19]}..."
      else
        puts "#{Time.now}: Warning: No HSM authorization to store in Redis"
      end

      set :response_key, app_response_key
    ensure
      response_client.quit
    end

    set :access_client, access_client
    set :revoked_devices_client, revoked_devices_client
    puts "#{Time.now}: Application server initialized"
  end

  # Enable CORS for all routes
  before do
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => ['GET', 'POST', 'OPTIONS'],
            'Access-Control-Allow-Headers' => 'Content-Type'
  end

  # Handle CORS preflight requests
  options '*' do
    200
  end

  # Health check endpoint
  get '/health' do
    content_type :json
    { status: 'healthy' }.to_json
  end

  # Foo/bar endpoint
  post '/foo/bar' do
    content_type :json

    begin
      # Read request body
      request.body.rewind
      message = request.body.read

      # Verify access request
      request_payload, token, nonce = settings.verifier.verify(message, TokenAttributes.new)

      # Check if device is revoked
      is_revoked = settings.revoked_devices_client.exists?(token.device)
      if is_revoked
        halt 403, { error: 'device revoked' }.to_json
      end

      # Check permissions
      user_permissions = token.attributes[:permissionsByRole][:user]
      unless user_permissions && user_permissions.include?('read')
        halt 401, { error: 'unauthorized' }.to_json
      end

      # Get server identity
      server_identity = settings.response_key.identity

      # Create response payload
      response_payload = ResponsePayload.new(
        was_foo: request_payload[:foo],
        was_bar: request_payload[:bar],
        server_name: 'ruby'
      )

      # Create and sign server response
      response = BetterAuth::Messages::ServerResponse.new_response(
        response_payload,
        server_identity,
        nonce
      )

      response.sign(settings.response_key)
      response.serialize
    rescue StandardError => e
      puts "Error handling request: #{e.message}"
      puts e.backtrace.join("\n")
      halt 500, { error: 'internal server error' }.to_json
    end
  end

  # Catch-all for 404
  not_found do
    content_type :json
    { error: 'not found' }.to_json
  end

  # Error handler
  error do
    content_type :json
    { error: 'internal server error' }.to_json
  end

  # Graceful shutdown handler
  at_exit do
    settings.access_client&.quit
  end

  # Start the server
  run! if app_file == $0
end
