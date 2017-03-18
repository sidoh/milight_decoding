#!/usr/bin/env ruby

DIR = File.expand_path(File.join(__FILE__, '..'))

Dir.glob(File.join(DIR, '**/*.txt')).each do |file|
  device = File.basename(File.dirname(file))

  file =~ /rgbcct_group(\d+)_([^_.]+)(_(seq_)?([^.]+))?\.txt/
  group, command, arg = [$1, $2, $5]

  File.open(file, 'r') do |f|
    while !f.eof? && line = f.readline
      packet = line.split(' ').map { |x| "'#{x.to_i(16)}'" }.join(', ')
      puts <<-SQL.gsub(/^\s+/, '')
        INSERT INTO packet_captures 
        ( 'device', 'command', 'arg', 'grp', 'b0', 'b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'b8' )
        VALUES
        ( '#{device}', '#{command}', '#{arg}', '#{group}', #{packet} );
      SQL
    end
  end
end
