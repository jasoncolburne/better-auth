require 'blake3-rb'
require 'base64'

module Crypto
  class Blake3
    def sum(message)
      # Convert byte array to string if needed
      message_str = message.is_a?(Array) ? message.pack('C*') : message
      hex_digest = Digest::Blake3.hexdigest(message_str)
      hash_bytes = [hex_digest].pack('H*')
      bytes = [0].pack('C') + hash_bytes
      encoded = Base64.urlsafe_encode64(bytes, padding: false)
      "E#{encoded[1..]}"
    end
  end
end
