require 'sinatra'
require 'redis'
require 'json'

class KeysServer < Sinatra::Base
  configure do
    set :port, 80
    set :bind, '0.0.0.0'

    # Configure Redis connection to DB 1 (where response keys are stored)
    redis_host = ENV['REDIS_HOST'] || 'redis:6379'
    host, port = redis_host.split(':')
    db = ENV['REDIS_DB_RESPONSE_KEYS'] || '1'
    set :redis, Redis.new(host: host, port: port.to_i, db: db.to_i)

    puts "Keys server configured to connect to Redis at #{redis_host}, DB #{db}"
  end

  # Enable CORS for all routes
  before do
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => ['GET', 'OPTIONS'],
            'Access-Control-Allow-Headers' => 'Content-Type'
    content_type :json
  end

  # Handle CORS preflight requests
  options '*' do
    200
  end

  # Health check endpoint
  get '/health' do
    begin
      # Test Redis connection
      settings.redis.ping
      { status: 'healthy', redis: 'connected' }.to_json
    rescue => e
      status 500
      { status: 'unhealthy', error: e.message }.to_json
    end
  end

  # Get all keys and values from Redis DB 1
  get '/keys' do
    begin
      print 'hello'

      keys = settings.redis.keys('*')

      # Use pipelined GET for efficiency
      if keys.empty?
        {}.to_json
      else
        values = settings.redis.pipelined do |pipeline|
          keys.each { |key| pipeline.get(key) }
        end

        # Build key-value map
        key_value_map = keys.zip(values).to_h
        key_value_map.to_json
      end
    rescue => e
      status 500
      { error: 'Failed to fetch keys', message: e.message }.to_json
    end
  end

  # Root endpoint
  get '/' do
    {
      service: 'keys',
      version: '1.0.0',
      endpoints: {
        health: '/health',
        keys: '/keys'
      }
    }.to_json
  end

  # Start the server
  run! if app_file == $0
end
