require 'net/ping'
require 'set'

require_relative 'milight'

def reachable?(host)
  check = Net::Ping::External.new(host, nil, 1)
  check.ping?
end

def reset_wifibox
  `curl -s -X PUT --data-binary 'FLAP' 10.133.8.153/pins/2 >/dev/null 2>/dev/null`
end

REQUIRED_PACKETS = 100
GROUP = 1

(99..100).each do |packet_to_get|
  file = get_file("color_1_seq_#{packet_to_get}", nil, GROUP)
  
  seen_keys = Set.new
  if File.exists?(file)
    File.read(file).split("\n").each { |x| seen_keys << x.split(' ').first }
  end
      
  puts "Processing: #{file}, seen #{seen_keys.size} keys"

  while seen_keys.size < REQUIRED_PACKETS
    puts "Seen #{seen_keys.size} / #{REQUIRED_PACKETS} packets"
    puts "Resetting wifi box"
    reset_wifibox
    
    print "Waiting for wifibox to connect"
    
    i = 1
    while i < 15 && !reachable?('10.133.8.133')
      i += 1
      print '.'
    end
    
    if i >= 10
      puts "Timed out waiting for device to become reachable"
      next
    end
    
    puts "Success!"
    puts "Trying to establish Milight connection"
    
    begin
      milight = Milight.new
      milight.start_session
    rescue Exception => e
      puts "Error: #{e}"
      next
    end
    
    i = 1
    
    while i <= packet_to_get
      print "Trying to get packet: #{i}"
      
      got_packet = false
      
      t = Thread.new do 
        begin
          packet = get_packet
          
          if i == packet_to_get
            key = packet.split(' ')[0]
            seen_keys << key
          end
          
          packet_file = get_file("color_1_seq_#{i}", nil, GROUP)
          File.open(packet_file, 'a') do |f|
            f.write "#{packet}\n"
          end
          
          got_packet = true
        rescue Exception => e
          puts "Exception getting packet: #{e}"
        end
      end
      
      sleep 2
      
      milight.send_command(Commands::COLOR.call(1), GROUP)
      
      start = Time.now
      while (Time.now - start) < 5 && %w(sleep run).include?(t.status)
        sleep 0.1
        print "."
      end
      
      if !got_packet
        puts
        puts "Didn't receive packet in time."
      end
      
      while t.status
        puts "Waiting for listener thread to die..."
        sleep 1
      end
      
      break if !got_packet
      
      i += 1
      puts
    end
  end
end