require 'pp'
require 'set'

CAPTURES_DIR = File.expand_path(File.join(__FILE__, "../../packet_captures"))
DEFAULT_DEVICE = 'sidoh_wifibox1'

def first_byte_determines_next(capture, count)
  capture
    .group_by { |x| x[0] }
    .map { |_, x| x.map { |packet| packet[1..count] } }
    .map(&:uniq)
    .map(&:length)
    .all? { |x| x == 1 }
end

def parse_capture(filename)
  File
    .read(filename)
    .split("\n")
    .map { |x| x.split(' ').map { |b| b.to_i(16) } }
end

def sum_bytes(b)
  b.split(' ').map { |x| x.to_i(16) }.reduce(&:+) % 0x100
end

def search_xor(bytes, base = (0..15))
  bytes = bytes.gsub(/[^A-F0-9]/i, '').scan(/.{2}/).map { |x| x.to_i(16) & 0xF }
  
  (0..15).map do |k|
    result = base.map do |x|
      (x ^ k)%16
    end
    
    bytes.map { |x| result.index(x) }
  end
end

def ror(x, count)
  (x >> count) | (x << (4 - count)) & 0xF
end

def parse_bytes(b)
  b.gsub(/[^A-F0-9.]/i, '').scan(/.{2}/).map do |x| 
    if x == '..'
      -1
    else
      x.to_i(16)
    end
  end
end

def search_zipped_sequence(seqs:, xor_range: (0..0xFF), s1_range: (0..0xFF), s2_range: (0..0xFF), expected_diff: 1)
  n = seqs.map(&:length).min
  misses = {}
  best = 123412341234
  
  s1_range.each do |s1|
    s2_range.each do |s2|
      seqs.each do |seq|
        m = 0
        
          (0...n).each do |i|
            this = decode(seq[i], s1, xor, s2, nil, false).first
            
            if last > -1 && (last - this) != expected_diff
              m += 1
            end
            
            last = this
          end
          
          break if m > best
      
        if m < best
          puts "new best: #{s1}, #{xor}, #{s2}: #{m}"
          best = m
        end
        
        misses[[s1,xor,s2]] = m
      end
    end
  end
  
  misses
end

def search_key_sequence(seq:, start_index: 0, s1_range: (0..0xFF), s2_range: (0..0xFF), offsets: [0], logging: false)
  bytes = parse_bytes(seq)
  matches = {}
  
  bytes.each_with_index do |byte, i|
    index = (i*4) + start_index
    x = xor_key(index)
    
    s1_range.each do |s1|
      s2_range.each do |s2|
        if offsets.include? decode("%02X" % byte, s1, x, s2, nil, false).first
          matches[[s1,s2]] ||= 0
          matches[[s1,s2]] += 1
          
          if logging
            printf "%3d (%02X): %02X %02X\n", index, index, s1, s2
          end
        end
      end
    end
  end
  
  puts if logging
  
  matches
end

def search_params(key_seqs:, s1: 0, start_range: (0..0xFF), max_s2_len: nil)
  puts "Searching for possible values" 
  starts = nil
  _start_range = start_range
  start_params = {}
  
  key_seqs.each_with_index do |seq, i|
    print "seq #{i}"
    
    start_params[i] = {}
    _max_s2_len = max_s2_len || (2 + seq.count('.')/2)
    
    puts
    puts _max_s2_len
    
    _start_range = Set.new(
      _start_range.select do |start|
        print '.' 
        params = search_key_sequence(seq: seq, s1_range: [s1], offsets: [start], start_index: i)
        
        if params.length <= _max_s2_len
          start_params[i][start] = params.keys.map(&:last)
          true
        end
      end
    )
    
    puts
    
    if _start_range.empty?
      puts "No valid start ranges."
      return
    end
  end
  
  puts 
  puts "Possible starts: #{_start_range.to_a}"
  puts start_params.inspect
  
  print "Searching for matches"
  
  r = key_seqs.each_with_index.map do |seq, i|
    ranges = _start_range.map do |start|
      params = start_params[i][start]
      values = seq.scan(/.{2}/).each_with_index.map do |byte, ix|
        r = nil
        full_ix = 4*ix + i
        if byte != '..'
          r = decode(byte, 0x00, xor_key(full_ix), params[0], nil, false).first
        end
        [full_ix, r]
      end
      
      v = to_ranges(values).group_by { |x| x[1] }
      v = Hash[v.map { |k,values| [k, values.map { |x| x[0] }] }]
      {
        s2: params[0], 
        ranges: v,
        start_value: start
      }
    end
    
    [i, ranges]
  end
  
  Hash[r]
end

def to_ranges(array)
  ranges = []
  if !array.empty?
    # Initialize the left and right endpoints of the range
    left, right = array.first, nil
    array.each do |obj|
      # If the right endpoint is set and obj is not equal to right's successor 
      # then we need to create a range.
      if right && (obj[0] != right[0]+4 || obj[1] != right[1])
        if !obj[1]
          right = [obj[0], right[1]]
        else
          ranges << [Range.new(left[0],right[0]), right[1]]
          left = obj
        end
      end
      if obj[1]
        right = obj
      end
    end
    ranges << [Range.new(left[0],right[0]), right[1]]
  end
  ranges
end

def calc_crc(data, poly) 
  data = data.split(' ').map { |x| x.to_i } if data.is_a?(String)
  state = 0;
  data.each do |byte|
    # byte = (byte >> 4) & 0xF
    byte = byte & 0xF
    4.times do
      if ((byte ^ state) & 0x01) == 0x01
        state = (state >> 1) ^ poly;
        #printf "^ "
      else 
        state = state >> 1;
        #printf "> "
      end
      #printf "%08b %016b // %02X %04X \n", byte, state, byte, state
      byte = byte >> 1;
    end
    #printf "---\n"
  end
  state
end

def search_id_by_sum(packets:, id1_vals:, id2_vals:, b1_vals:, device: DEFAULT_DEVICE, group: 1)
  possible_vals = b1_vals.product(id1_vals, id2_vals)
  
  printf "%d possible value combinations\n", possible_vals.length
  
  packets.each_with_index do |packets, i|
    packet = packets.split(' ').map { |x| x.to_i(16) }
    checksum = packet.last
    packet = packet[0..-2]
    
    printf "Processing packet %d", i
    last_progress = 0
    i = 0
    
    possible_vals = possible_vals.select do |v|
      progress = (10*(i += 1)/possible_vals.length.to_f).floor
      
      if progress != last_progress
        print '.'
        last_progress = progress
      end
      
      b1, id1, id2 = v
      _packet = packet.clone
      # _packet[0] = xor_key(_packet[0])
      _packet[1] = b1
      _packet[2] = id1
      _packet[3] = id2
      
      _packet.first(8).reduce(&:+) == _packet.last
    end
    
    puts
  end
  
  possible_vals
end

def send_packet(packet)
  if packet.is_a?(Array)
    packet = packet.map { |x| x.is_a?(String) ? x : sprintf('%02X', x) }.join(' ')
  end
  
  pp packet
  
  `curl -s -X PUT --data-binary '{"packet":"#{packet}", "num_repeats":50}' 10.133.8.167/send_raw/rgb_cct` 
end

def search_id_by_crc(packets:, id1_vals:, id2_vals:, b1_vals:, device: DEFAULT_DEVICE, group: 1)
  possible_vals = b1_vals.product(id1_vals, id2_vals)
  
  printf "%d possible value combinations\n", possible_vals.length
  
  packets.each_with_index do |packets, i|
    packet = packets.split(' ').map { |x| x.to_i(16) }
    checksum = packet.last
    packet = packet[0..-2]
    
    printf "Processing packet %d", i
    last_progress = 0
    i = 0
    
    possible_vals = possible_vals.select do |v|
      progress = (10*(i += 1)/possible_vals.length.to_f).floor
      
      if progress != last_progress
        print '.'
        last_progress = progress
      end
      
      b1, id1, id2 = v
      _packet = packet.clone
      # _packet[0] = xor_key(_packet[0])
      _packet[1] = b1
      _packet[2] = id1
      _packet[3] = id2
      
      (0..0xFF).any? do |poly|
        crc = calc_crc(_packet, poly)
        crc&0xF == checksum&0xF && (crc&0x70==checksum&0x70)
      end
    end
    
    puts
  end
  
  possible_vals
end

def search_sequence(seq:, mask: 0xFF, start: 0, increments: 1, decoded_seq: nil, xor_range: (0..0xFF), s1_range: (0..0xFF), s2_range: (0..0xFF), invert_key: false, logging: false)
  bytes = parse_bytes(seq)
  
  l = 0
  fns = []
  num_bytes = bytes.count { |x| x >= 0 }
  
  xor_range.each do |xor|
    xor = (0xFF ^ xor) if invert_key
    
    if logging
      puts
      print "#{xor}: "
    end
    
    s1_range.each do |s1|
      print "." if logging && (s1 % 0x10) == 0
      
      s2_range.each do |s2|
        found = true
        num_matches = 0
        
        bytes.each_with_index do |x, i|
          next if bytes[i] == -1
          
          if decoded_seq
            x = decoded_seq[i]
          else
            x = start + (i*increments)
          end
          
          v = (x + s1) % 0x100
          v = (v ^ xor)
          v = (v + s2) % 0x100
          
          if (bytes[i]&mask) != (v&mask)
            found = false
            if ((bytes.length - i) + num_matches) < l
              break
            end
          else 
            num_matches += 1
          end
        end
        
        if num_matches >= l
          if num_matches > l
            fns = [] if num_matches > l
            print "(New best - #{l},#{s1},#{xor},#{s2})" if logging
          end
          
          l = num_matches
          fns << {
            a: s1,
            x: xor,
            b: s2,
            exact: found
          }
        end
      end
    end
  end
  
  if logging
    puts
    puts "Best found: #{l} (#{fns.first[:exact] ? "exact" : "inexact"})"
    
    fns.each do |fn|
      printf "0x%02X\t0x%02X\t0x%02X\n", fn[:a], fn[:x], fn[:b]
    end
  end
  
  {
    scramble_fns: fns,
    num_matches: l,
    num_misses: num_bytes - l
  }
end

def print_matches(bytes, a, b, c, i_fn = ->(i) { i })
  fn = ->(x) { ((((x+a)%0x100)^b) + c)%0x100 }
  
  parse_bytes(bytes).each_with_index do |x,i| 
    if x != -1
      v = "%02X" % fn.call(i_fn.call(i))
    else
      v = ".."
    end
    
    xv = (x != -1 ? "%02X" % x : '..')
      
    printf "%02X %s %s %s\n", i_fn.call(i), xv, v, xv==v ? '' : '*'
  end
end

def decode(bytes, a, b, c, matches = nil, _print = true)
  fn_inv = ->(x) do 
    w = (x + (0x100 - c))%0x100
    w = w ^ b
    w = (w + (0x100 - a))%0x100
  end
  
  bytes.scan(/.{2}/).each_with_index.map do |x,i| 
    if x != '..'
      v = fn_inv.call(x.to_i(16)) 
      w = matches.nil? ? i : matches[i]
      
      printf "%02X %s %02X %s\n", w, x, v, (w == v ? '✔' : '') if _print
      v
    else
      puts ".. .. .."
    end
  end
end

def get_sequence(type:, key:, col: nil, arg_range: (0..0xFF), group: 1, extract_fn: nil)
  s = ""
  key = ("%02X" % key) if !key.is_a?(String)
  
  arg_range.each do |arg|
    found = false
    file = get_packet_capture_file(type: type, group: group, arg: arg)
    
    if File.exists?(file)
      File.open(file, 'r') do |file|
        while !file.eof? && line = file.readline
          fields = line.split(' ')
          if fields[0] == key.to_s
            found = true
            
            if extract_fn
              s += extract_fn.call(fields)
            else
              s += fields[col]
            end
            
            break
          end
        end
      end
    end
      
    if !found
      s += '..'
    end
  end
  
  s.gsub(/([^.])\.+$/, '\1')
end

def get_packet_capture_file(type:, group:, arg: nil, device: DEFAULT_DEVICE)
  "#{CAPTURES_DIR}/#{device}/rgbcct_group#{group}_#{type}#{arg.nil? ? '' : "_#{arg}"}.txt"
end

def get_group_sequence(type:, col:, key:, arg: nil, group_range: (1..4))
  s = ""
  key = ("%02X" % key) if !key.is_a?(String)
  
  group_range.each do |group|
    found = false
    file = get_packet_capture_file(type: type, group: group, arg: arg)
    
    if File.exists?(file)
      File.open(file, 'r') do |file|
        while !file.eof? && line = file.readline
          fields = line.split(' ')
          if fields[0] == key.to_s
            found = true
            s += fields[col]
            break
          end
        end
      end
    end
      
    if !found
      s += '..'
    end
  end
  
  s
end

def get_key_sequence(type:, col:, key_col: 0, arg: nil, group: 1, key_range: (0..0xFF), device: DEFAULT_DEVICE)
  lines_by_key = {}
  
  File.open(get_packet_capture_file(type: type, group: group, arg: arg, device: device), 'r') do |file|
    while !file.eof? && line = file.readline
      fields = line.split(' ')
      lines_by_key[fields[key_col].to_i(16)] = fields
    end
  end
  
  s = ""
  
  key_range.each do |key|
    if fields = lines_by_key[key]
      s += fields[col]
    else
      s += '..'
    end
  end
  
  s
end

def xor_key(b0)
  # Generate most significant nibble
  shift = 0#(b0 & 0x0F) < 0x04 ? 0 : 1
  x = (((b0 & 0xF0) >> 4) + shift + 6) % 8
  msn = (((4 + x) ^ 1) & 0x0F) << 4

  # Generate least significant nibble
  lsn = ((((b0 & 0xF) + 4)^2) & 0x0F)
  
  msn | lsn
end