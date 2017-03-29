require 'socket'
require 'set'
require 'net/http'

STD_COMMAND_PREFIX = [ 0x31, 0x00, 0x00, 0x08 ]
STD_COMMAND_SUFFIX = [ 0x00, 0x00, 0x00 ]

class Commands
  def self.std_command(*cmd)
    ->() { STD_COMMAND_PREFIX + cmd + STD_COMMAND_SUFFIX }
  end

  def self.arg_command(prefix)
    ->(val) { STD_COMMAND_PREFIX + [prefix, val] + STD_COMMAND_SUFFIX }
  end

  VALUES = [
    LIGHT_ON = std_command(0x04, 0x01),
    LIGHT_OFF = std_command(0x04, 0x02),
    SATURATION = arg_command(0x02),
    BRIGHTNESS = arg_command(0x03),
    KELVIN = arg_command(0x05),
    WHITE_ON = std_command(0x05, 0x64),
    NIGHT_ON = std_command(0x04, 0x05),
    LINK = ->() { [ 0x3D, 0x00, 0x00, 0x08, 0x00, 0x00 ] + STD_COMMAND_SUFFIX },
    UNLINK = ->() { [ 0x3D, 0x00, 0x00, 0x08, 0x00, 0x00 ] + STD_COMMAND_SUFFIX },
    COLOR = ->(value) { STD_COMMAND_PREFIX + [0x01] + ([value]*4) },
    MODE = arg_command(0x06),
    MODE_SPEED_UP = std_command(0x04, 0x03),
    MODE_SPEED_DOWN = std_command(0x04, 0x04),
    
    LIGHT_ON_HELD = std_command(0x84, 0x11),
    LIGHT_OFF_HELD = std_command(0x84, 0x02),
    SATURATION_HELD = arg_command(0x82),
    BRIGHTNESS_HELD = arg_command(0x83),
    KELVIN_HELD = arg_command(0x85),
    WHITE_ON_HELD = std_command(0x85, 0x64),
    NIGHT_ON_HELD = std_command(0x84, 0x05),
    COLOR_HELD = ->(value) { STD_COMMAND_PREFIX + [0x81] + ([value]*4) },
    MODE_HELD = arg_command(0x86),
    MODE_SPEED_UP_HELD = std_command(0x84, 0x03),
    MODE_SPEED_DOWN_HELD = std_command(0x84, 0x04),
  ]
end

class Milight
  ADDR = ['<broadcast>', 5987]
  
  attr_reader :socket
  
  def initialize(host = ADDR[0], port = ADDR[1])
    @socket = UDPSocket.new
    @host = host
    @port = port
    
    if host == ADDR[0]
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
    end
    
    @sequence = 0
  end
  
  def hex_to_bytes(s)
    s.strip.split(' ').map { |x| x.to_i(16) }.pack('C*')
  end

  def send(msg)
    socket.send(msg, 0, @host, @port)
  end

  def recv
    socket.recvfrom(1000)[0]
  end

  def start_session
    tries = 5
    begin
      Timeout.timeout(5) do
        send(hex_to_bytes("20 00 00 00 16 02 62 3A D5 ED A3 01 AE 08 2D 46 61 41 A7 F6 DC AF D3 E6 00 00 1E"))
        msg = recv
        @session = msg[-3..-2].bytes
      end
    rescue Exception => e
      puts "Error: #{e}"
      retry if (tries -= 1) > 0
    end
  end

  def send_command(cmd, zone = 0)
    start_session if !@session
    
    msg = [0x80, 0, 0, 0, 0x11, @session[0], @session[1], 0, @sequence, 0]
    msg += cmd
    msg += [zone,0]
    msg += [msg[-11..-1].reduce(&:+)&0xFF]
    
    send(msg.pack('C*'))
    
    @sequence = (@sequence + 1) % 0xFF
    
    #recv
  end
end

def get_file(cmd, value, group)
  name = "../../packet_captures/sidoh_wifibox1/rgbcct_group#{group}_#{cmd}#{value.nil? ? "" : "_#{value}"}.txt"
  File.expand_path(File.join(__FILE__, name))
end

def get_packet
  uri = URI('http://10.133.8.167/gateway_traffic/rgb_cct')
  
  http = Net::HTTP.start(uri.host, uri.port) do |http|
    http.read_timeout = 5
    request = Net::HTTP::Get.new(uri)
    return http.request(request).body.split("\n").last.strip
  end
  
  return nil
end
