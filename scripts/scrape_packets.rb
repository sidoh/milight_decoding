require_relative 'milight'

milight = Milight.new

GROUP = 1

class Command
  attr_reader :bytes, :name, :file
  
  def initialize(name, *args)
    @bytes = Commands.const_get(name).call(*args)
    @name = name.downcase.gsub('light_', '')
    @file = get_file(@name, args.first, GROUP)
  end
end

commands = []

%w(
  LIGHT_ON_HELD 
  LIGHT_OFF_HELD
  NIGHT_ON_HELD
  MODE_SPEED_UP_HELD
  MODE_SPEED_DOWN_HELD
).each do |cmd|
  commands << Command.new(cmd)
end

%w(
  MODE_HELD
).each do |cmd|
  (0..0x9).each do |arg|
    commands << Command.new(cmd, arg)
  end
end

%w(
  BRIGHTNESS_HELD
  SATURATION_HELD
  KELVIN_HELD
).each do |cmd|
  (0..0x6).each do |arg|
    commands << Command.new(cmd, (arg << 4) | (arg))
    commands << Command.new(cmd, (arg << 4) | ((arg + 1)%0xF))
  end
end

%w(
  COLOR_HELD
).each do |cmd|
  (0..0xF).each do |arg|
    commands << Command.new(cmd, (arg << 4) | (arg))
    commands << Command.new(cmd, (arg << 4) | ((arg + 1)%0xF))
  end
end

(0..0x10).each do |required_packets|
  commands.each do |cmd|
    seen_keys = Set.new
    last_val = 0
    
    file = cmd.file
    
    if File.exists?(file)
      File.read(file).split("\n").each { |x| seen_keys << x.split(' ').first }
    end
    
    puts "Processing: #{file}"
    
    File.open(file, 'a') do |f|
      while seen_keys.size < required_packets*0x10
        t = Thread.new do 
          packet = get_packet
          key = packet.split(' ')[0]
          seen_keys << key
          f.write "#{packet}\n"
          f.flush
        end
        
        while %w(sleep run).include?(t.status)
          milight.send_command(cmd.bytes, GROUP)
          sleep 0.1
          print "."
        end
        
        print '*'
        
        puts "\n#{file} - #{seen_keys.length}" if last_val < seen_keys.length
        last_val = seen_keys.length
      end
    end
  end
end

# 10000.times do
#   milight.send_command(, 1).inspect
#   print "."
#   sleep 0.1
# end