#!/usr/bin/env ruby

require "base64"
require "json"
require "openssl"

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def fixed_width_integer(value, width)
  hex = value.to_i.to_s(16)
  hex = "0#{hex}" if hex.length.odd?
  bytes = [hex].pack("H*")
  abort "ES256 signature component exceeded #{width} bytes" if bytes.bytesize > width

  ("\0" * (width - bytes.bytesize)) + bytes
end

issuer_id, key_id, private_key_path = ARGV
if [issuer_id, key_id, private_key_path].any? { |value| value.nil? || value.empty? }
  abort "usage: app-store-connect-jwt.rb ISSUER_ID KEY_ID PRIVATE_KEY_PATH"
end

now = Time.now.to_i
header = base64url(JSON.generate(alg: "ES256", kid: key_id, typ: "JWT"))
payload = base64url(
  JSON.generate(
    iss: issuer_id,
    iat: now - 30,
    exp: now + (15 * 60),
    aud: "appstoreconnect-v1"
  )
)
signing_input = "#{header}.#{payload}"

private_key = OpenSSL::PKey.read(File.read(private_key_path))
der_signature = private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
sequence = OpenSSL::ASN1.decode(der_signature)
raw_signature = sequence.value.map { |integer| fixed_width_integer(integer.value, 32) }.join

puts "#{signing_input}.#{base64url(raw_signature)}"
