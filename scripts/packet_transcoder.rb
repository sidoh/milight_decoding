class PacketTranscoder
  module S2Bases
    ARGUMENT = [0x5A, 0x22, 0x30, 0x11]
    GROUP = [0xAF, 0x04, 0xDD, 0x07]
    COMMAND = [0xAF, 0x03, 0x1D, 0xF3]
    SEQUENCE = [0x04, 0xD8, 0x71, 0x42]
    
    B1 = [0x45, 0x1F, 0x14, 0x5C]
    
    ID1 = [0xAB, 0x49, 0x63, 0x91]
    ID2 = [0x2D, 0x1F, 0x4A, 0xEB]
    
    CHECKSUM = [0xE1, 0x93, 0xB8, 0xE4]
  end
  
  module Commands
    VALUES = [
      ON = 1,
      OFF = 2,
      COLOR = 3,
      SATURATION = 4,
      BRIGHTNESS = 5,
      KELVIN = 6,
      MODE = 7,
      MODE_SPEED_UP = 8,
      MODE_SPEED_DOWN = 9,
    ]
    
    PACKET_KEY = {
      ON => 1,
      OFF => 1,
      MODE_SPEED_UP => 1,
      MODE_SPEED_DOWN => 1,
      COLOR => 2,
      SATURATION => 4,
      BRIGHTNESS => 4,
      KELVIN => 3,
      MODE => 5
    }
    
    RANGE_START = {
      ON => 0xC0,
      OFF => 0xC5,
      COLOR => 0x15,
      SATURATION => 0,
      BRIGHTNESS => 0x4F,
      KELVIN => 0x4C,
      MODE => 0,
      MODE_SPEED_UP => 0xCA,
      MODE_SPEED_DOWN => 0xCB
    }
    
    def self.from_packet_key(cmd)
      PACKET_KEY.each do |k, v|
        return k if cmd == v
      end
    end
  end
  
  class Transcoder
    def initialize(s1, s2_calculator, xor_calculator = XorCalculator.new)
      if s1.is_a?(Numeric)
        @s1_calculator = StaticS1Calculator.new(s1)
      else
        @s1_calculator = s1
      end
      
      @xor_calculator = xor_calculator
      @s2_calculator = s2_calculator
    end
    
    def decode(scramble_key, byte)
      s1 = @s1_calculator.value_for(scramble_key)
      s2 = @s2_calculator.value_for(scramble_key)
      xor_key = @xor_calculator.value_for(scramble_key)
      Transcoder.decode_byte(byte, s1, xor_key, s2)
    end
    
    def encode(scramble_key, byte)
      s1 = @s1_calculator.value_for(scramble_key)
      s2 = @s2_calculator.value_for(scramble_key)
      xor_key = @xor_calculator.value_for(scramble_key)
      e = Transcoder.encode_byte(byte, s1, xor_key, s2)
      e
    end
  
    def self.encode_byte(x, a, b, c)
      v = (x + a) % 0x100
      v = v ^ b
      v = (v + c) % 0x100
    end
  
    def self.decode_byte(x, a, b, c)
      v = (x + (0x100 - c))%0x100
      v = v ^ b
      v = (v + (0x100 - a))%0x100
    end
  end
  
  class ChecksumS1Calculator
    def value_for(scramble_key)
      (scramble_key & 0x7F) + 3
    end
  end
  
  class StaticS1Calculator
    def initialize(value)
      @value = value
    end
    
    def value_for(scramble_key)
      @value
    end
  end
      
  
  class S2Calculator
    def initialize(bases, range_start, range_end, offset = 0x80)
      @bases = bases
      @range_start = range_start
      @range_end = range_end
      @offset = offset
    end
    
    def value_for(scramble_key)
      base = @bases[ (scramble_key % 4) ]
      
      if scramble_key >= @range_start && scramble_key <= @range_end
        base += @offset
      end
      
      base
    end
  end
  
  class XorCalculator
    def initialize(invert = false)
      @invert = invert
    end
    
def value_for(p0)
  # Generate most significant nibble
  shift = (p0 & 0x0F) < 0x04 ? 0 : 1
  x = (((p0 & 0xF0) >> 4) + shift + 6) % 8
  msn = (((4 + x) ^ 1) & 0x0F) << 4

  # Generate least significant nibble
  lsn = ((((p0 & 0xF) + 4)^2) & 0x0F)

  msn | lsn
end
  end
  
  module Transcoders
    POSITION_TRANSCODERS = {
      1 => Transcoder.new(0, S2Calculator.new(S2Bases::B1, 0x54, 0xD3)),
      2 => Transcoder.new(0, S2Calculator.new(S2Bases::ID1, 0x54, 0xD3)),
      3 => Transcoder.new(0, S2Calculator.new(S2Bases::ID2, 0x14, 0x93)),
      4 => Transcoder.new(0, S2Calculator.new(S2Bases::COMMAND, 0x54, 0xD3)),
      6 => Transcoder.new(0, S2Calculator.new(S2Bases::SEQUENCE, 0x54, 0xD3)),
      7 => Transcoder.new(0, S2Calculator.new(S2Bases::GROUP, 0x54, 0xD3)),
      8 => Transcoder.new(2, S2Calculator.new(S2Bases::CHECKSUM, 0x100, 0x100))
    }
    
    COMMAND_TRANSCODERS = {
      Commands::ON => Transcoder.new(0, S2Calculator.new(S2Bases::ON_OFF, 0x14, 0x93)),
      Commands::OFF => Transcoder.new(0, S2Calculator.new(S2Bases::ON_OFF, 0x14, 0x93)),
      Commands::COLOR => Transcoder.new(0, S2Calculator.new(S2Bases::ARGUMENT, 0x14, 0x93)),
      Commands::BRIGHTNESS => Transcoder.new(0, S2Calculator.new(S2Bases::ARGUMENT, 0x54, 0xD3)),
      Commands::SATURATION => Transcoder.new(0, S2Calculator.new(S2Bases::ARGUMENT, 0x54, 0xD3)),
      Commands::KELVIN => Transcoder.new(0, S2Calculator.new(S2Bases::ARGUMENT, 0x14, 0x93)),
      Commands::MODE => Transcoder.new(0, S2Calculator.new(S2Bases::MODE, 0x14, 0x93))
    }
  end
  
  def decode_packet(bytes)
    b = Array.new(bytes.length)
    key = bytes[0]
    
    b[0] = key
    
    Transcoders::POSITION_TRANSCODERS.each do |i, coder|
      b[i] = coder.decode(key, bytes[i])
    end
    
    command = b[4]
    command_decoder = Transcoders::COMMAND_TRANSCODERS[Commands.from_packet_key(command & 0xF)]
    
    if !command_decoder
      $stderr.puts "Unknown command: #{command}"
    end
    
    arg = command_decoder.decode(key, bytes[5])
    
    b[5] = arg
    
    # Saturation starts has lowest/highest flipped and is offset from 0
    if command == Commands::PACKET_KEY[Commands::SATURATION] && (arg <= 0x31 || arg >= 0xCD)
      arg = 0x64 - ((0x33 + arg) % 0x100)
    end
    
    b
  end
  
  def encode_packet(packet)
    key = packet[0]
    command = packet[4]
    
    Transcoders::POSITION_TRANSCODERS.each do |i, coder|
      packet[i] = coder.encode(key, packet[i])
    end
    
    packet[5] = Transcoders::COMMAND_TRANSCODERS[Commands.from_packet_key(command & 0xF)].encode(key, packet[5])
    
    packet
  end
  
  def build_packet(key, device_id, command, arg, group, seq)
    packet = Array.new(9)
    arg = arg || 0
    
    encoded_arg = (arg + Commands::RANGE_START[command]) % 0x100
    
    if command == Commands::SATURATION
      encoded_arg = (encoded_arg - 0x33) % 0x100
    end
    
    if command == Commands::KELVIN
      encoded_arg = (encoded_arg * 2) % 0x100
    end
    
    if command == Commands::ON || command == Commands::OFF
      encoded_arg = encoded_arg + group
    end
    
    if command == Commands::MODE
      encoded_arg = 0xC0 + ((8 + arg)%9)
    end
    
    packet[0] = key
    packet[1] = 0x20
    packet[2] = (device_id >> 8)&0xFF
    packet[3] = (device_id) & 0xFF
    packet[4] = Commands::PACKET_KEY[command]
    packet[5] = encoded_arg
    packet[6] = seq
    packet[7] = group
    packet[8] = (packet[1..7].reduce(&:+) + xor_key(key)) % 0x100
    
    encode_packet(packet)
  end
end

