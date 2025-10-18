require 'zlib'
require 'base64'
require 'stringio'

module AppEncoding
  class TokenEncoder
    def encode(object)
      compressed_buffer = StringIO.new
      gz = Zlib::GzipWriter.new(compressed_buffer, Zlib::BEST_COMPRESSION)
      gz.write(object)
      gz.close

      Base64.urlsafe_encode64(compressed_buffer.string, padding: false)
    end

    def decode(token)
      gzipped_token = Base64.urlsafe_decode64(token)

      compressed_buffer = StringIO.new(gzipped_token)
      gz = Zlib::GzipReader.new(compressed_buffer)
      result = gz.read
      gz.close

      result
    end

    def signature_length(token)
      throw 'token too short' if token.length < 88
      throw 'invalid token prefix' unless token[..1] == '0I'

      # For secp256r1 signatures, the length is always 88 characters
      88
    end
  end
end
