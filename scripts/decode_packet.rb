require_relative 'packet_transcoder'

bytes = gets.strip.gsub(' ', '').scan(/.{2}/).map { |x| x.to_i(16) }

puts PacketTranscoder.new.decode_packet(bytes).map { |x| "%02X" % x }.join(' ')