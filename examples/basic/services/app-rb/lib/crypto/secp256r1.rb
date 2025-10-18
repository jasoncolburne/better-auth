require 'openssl'
require 'base64'

module Crypto
  class Secp256r1
    def initialize
      @private_key = OpenSSL::PKey::EC.generate('prime256v1')
    end

    def verifier
      Secp256r1Verifier.new
    end

    def identity
      public
    end

    def public
      public_key = @private_key.public_key
      public_key_bytes = public_key.to_bn.to_s(2)

      compressed_key = compress_public_key(public_key_bytes)
      base64_public_key = Base64.urlsafe_encode64(compressed_key, padding: false)
      "1AAI#{base64_public_key}"
    end

    def sign(message)
      asn1_signature = @private_key.sign(OpenSSL::Digest.new('SHA256'), message.pack('C*'))

      # Parse ASN.1 signature to get R and S
      asn1 = OpenSSL::ASN1.decode(asn1_signature)
      r = asn1.value[0].value.to_s(2)
      s = asn1.value[1].value.to_s(2)

      # Pad to 32 bytes
      r = r.rjust(32, "\x00")
      s = s.rjust(32, "\x00")

      signature_bytes = "\u0000\u0000#{r}#{s}"
      base64_signature = Base64.urlsafe_encode64(signature_bytes, padding: false)
      "0I#{base64_signature[2..]}"
    end

    private

    def compress_public_key(pub_key_bytes)
      raise 'invalid length' unless pub_key_bytes.length == 65
      raise 'invalid byte header' unless pub_key_bytes[0].ord == 0x04

      x = pub_key_bytes[1..32]
      y = pub_key_bytes[33..64]

      y_parity = y[-1].ord & 0x01
      prefix = y_parity.zero? ? "\x02" : "\x03"

      prefix + x
    end
  end

  class Secp256r1Verifier
    def verify(signature, public_key, message)
      public_key_bytes = Base64.urlsafe_decode64(public_key[4..])

      # Decompress the public key to get full 65-byte uncompressed format
      curve = OpenSSL::PKey::EC::Group.new('prime256v1')
      point = OpenSSL::PKey::EC::Point.new(curve, OpenSSL::BN.new(public_key_bytes, 2))
      uncompressed_bytes = point.to_octet_string(:uncompressed)

      # Create EC public key - OpenSSL 3.0 compatible approach
      # Build DER format: SEQUENCE { SEQUENCE { OID, OID }, BIT STRING }
      oid_ec_public_key = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01].pack('C*')
      oid_prime256v1 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07].pack('C*')
      algorithm = OpenSSL::ASN1::Sequence.new([
                                                OpenSSL::ASN1.decode(oid_ec_public_key),
                                                OpenSSL::ASN1.decode(oid_prime256v1)
                                              ])
      subject_public_key = OpenSSL::ASN1::BitString.new(uncompressed_bytes)
      ec_key_der = OpenSSL::ASN1::Sequence.new([algorithm, subject_public_key]).to_der

      ec_key = OpenSSL::PKey::EC.new(ec_key_der)

      signature_bytes = Base64.urlsafe_decode64(signature)
      r = OpenSSL::BN.new(signature_bytes[2..33], 2)
      s = OpenSSL::BN.new(signature_bytes[34..65], 2)

      # Create ASN.1 signature
      asn1_sig = OpenSSL::ASN1::Sequence.new([
                                               OpenSSL::ASN1::Integer.new(r),
                                               OpenSSL::ASN1::Integer.new(s)
                                             ]).to_der

      raise 'invalid signature' unless ec_key.verify(OpenSSL::Digest.new('SHA256'), asn1_sig, message.pack('C*'))

      nil
    end
  end
end
