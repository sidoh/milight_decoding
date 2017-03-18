CRC_POLY = 0x8408

def calc_crc(data, poly = CRC_POLY) 
  state = 0;
  data.each do |byte|
    8.times do
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

input = gets.strip

# [0x1D].each do |poly|
#   r = calc_crc([input].pack('H*').bytes, poly)
#   printf "%02X: %04X (%d)\n", poly, r, r
# end

input.scan(/.{2}/).each do |byte|
  printf "%02X\n", calc_crc([byte.to_i(16)], 0x2F)
end
