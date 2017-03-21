require_relative 'packet_transcoder'

PATH = File.expand_path(File.join(__FILE__, '../../packet_captures'))

decoder = PacketTranscoder.new

Dir.glob("#{PATH}/**/*.txt").each do |file|
  File.open(file, 'r') do |f|
    while !f.eof? && line = f.readline
      packet = line.split(' ').map { |x| x.to_i(16) }
      decoded = decoder.decode_packet(packet)
      computed = decoder.encode_packet(decoded)
      
      if packet[8] != computed[8]
        puts "-----------"
        puts "Mismatched checksum: "
        puts "File              : #{file}"
        puts "Packet            : #{line}"
        puts "Decoded Packet    : #{decoded.map { |x| '%02X' % x }.join(' ')}"
        puts "Re-encoded        : #{computed.map { |x| '%02X' % x }.join(' ')}"
      end
    end
  end
end