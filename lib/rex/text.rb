require 'digest/md5'
require 'stringio'

begin
	require 'iconv'
	require 'zlib'
rescue LoadError
end

module Rex

###
#
# This class formats text in various fashions and also provides
# a mechanism for wrapping text at a given column.
#
###
module Text
	@@codepage_map_cache = nil
	
	##
	#
	# Constants
	#
	##

	States = ["AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA", "HI",
		"IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN",
		"MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", "OH",
		"OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA",
		"WI", "WV", "WY"]
	UpperAlpha   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	LowerAlpha   = "abcdefghijklmnopqrstuvwxyz"
	Numerals     = "0123456789"
	Alpha        = UpperAlpha + LowerAlpha
	AlphaNumeric = Alpha + Numerals
	HighAscii    = [*(0x80 .. 0xff)].pack("C*")
	DefaultWrap  = 60
	AllChars     = [*(0x00 .. 0xff)].pack("C*")

	DefaultPatternSets = [ Rex::Text::UpperAlpha, Rex::Text::LowerAlpha, Rex::Text::Numerals ]
	
	##
	#
	# Serialization
	#
	##

	#
	# Converts a raw string into a ruby buffer
	#
	def self.to_ruby(str, wrap = DefaultWrap, name = "buf")
		return hexify(str, wrap, '"', '" +', "#{name} = \n", '"')
	end

	#
	# Creates a ruby-style comment
	#
	def self.to_ruby_comment(str, wrap = DefaultWrap)
		return wordwrap(str, 0, wrap, '', '# ')
	end

	#
	# Converts a raw string into a C buffer
	#
	def self.to_c(str, wrap = DefaultWrap, name = "buf")
		return hexify(str, wrap, '"', '"', "unsigned char #{name}[] = \n", '";')
	end

	#
	# Creates a c-style comment
	#
	def self.to_c_comment(str, wrap = DefaultWrap)
		return "/*\n" + wordwrap(str, 0, wrap, '', ' * ') + " */\n"
	end
	
	#
	# Creates a javascript-style comment
	#
	def self.to_js_comment(str, wrap = DefaultWrap)
		return wordwrap(str, 0, wrap, '', '// ')
	end
	
	#
	# Converts a raw string into a perl buffer
	#
	def self.to_perl(str, wrap = DefaultWrap, name = "buf")
		return hexify(str, wrap, '"', '" .', "my $#{name} = \n", '";')
	end

	#
	# Converts a raw string into a java byte array
	#
	def self.to_java(str, name = "shell")
		buff = "byte #{name}[] = new byte[]\n{\n"
		cnt = 0
		max = 0
		str.unpack('C*').each do |c|
			buff << ", " if max > 0
			buff << "\t" if max == 0
			buff << sprintf('(byte) 0x%.2x', c)
			max +=1
			cnt +=1 
			
			if (max > 7)	
				buff << ",\n" if cnt != str.length 
				max = 0
			end
		end
		buff << "\n};\n"
		return buff	
	end
	
	#
	# Creates a perl-style comment
	#
	def self.to_perl_comment(str, wrap = DefaultWrap)
		return wordwrap(str, 0, wrap, '', '# ')
	end

	#
	# Returns the raw string
	#
	def self.to_raw(str)
		return str
	end

	#
	# Converts ISO-8859-1 to UTF-8
	#
	def self.to_utf8(str)
		begin
			Iconv.iconv("utf-8","iso-8859-1", str).join(" ")
		rescue
			raise ::RuntimeError, "Your installation does not support iconv (needed for utf8 conversion)"
		end
	end

	#
	# Converts ASCII to EBCDIC
	#
	def self.to_ebcdic(str)
		begin
			Iconv.iconv("EBCDIC-US", "ASCII", str).first
		rescue ::Iconv::IllegalSequence => e
			raise e
		rescue
			raise ::RuntimeError, "Your installation does not support iconv (needed for EBCDIC conversion)"
		end
	end

	# 
	# Converts EBCIDC to ASCII
	#
	def self.from_ebcdic(str)
		begin
			Iconv.iconv("ASCII", "EBCDIC-US", str).first
		rescue ::Iconv::IllegalSequence => e
			raise e
		rescue
			raise ::RuntimeError, "Your installation does not support iconv (needed for EBCDIC conversion)"
		end
	end
	
	#
	# Returns a unicode escaped string for Javascript
	#
	def self.to_unescape(data, endian=ENDIAN_LITTLE)
		data << "\x41" if (data.length % 2 != 0)
		dptr = 0
		buff = ''
		while (dptr < data.length)
			c1 = data[dptr,1].unpack("C*")[0]
			dptr += 1
			c2 = data[dptr,1].unpack("C*")[0]
			dptr += 1
			
			if (endian == ENDIAN_LITTLE)
				buff << sprintf('%%u%.2x%.2x', c2, c1)
			else
				buff << sprintf('%%u%.2x%.2x', c1, c2)
			end
		end
		return buff	
	end

	#
	# Returns the hex version of the supplied string
	#
	def self.to_hex(str, prefix = "\\x", count = 1)
		raise ::RuntimeError, "unable to chunk into #{count} byte chunks" if ((str.length % count) > 0)

		# XXX: Regexp.new is used here since using /.{#{count}}/o would compile
		# the regex the first time it is used and never check again.  Since we
		# want to know how many to capture on every instance, we do it this
		# way.
		return str.unpack('H*')[0].gsub(Regexp.new(".{#{count * 2}}", nil, 'n')) { |s| prefix + s }
	end

	#
	# Converts standard ASCII text to a unicode string.  
	#
	# Supported unicode types include: utf-16le, utf16-be, utf32-le, utf32-be, utf-7, and utf-8
	# 
	# Providing 'mode' provides hints to the actual encoder as to how it should encode the string.  Only UTF-7 and UTF-8 use "mode".
	# 
	# utf-7 by default does not encode alphanumeric and a few other characters.  By specifying the mode of "all", then all of the characters are encoded, not just the non-alphanumeric set.
	#	to_unicode(str, 'utf-7', 'all')
	# 
	# utf-8 specifies that alphanumeric characters are used directly, eg "a" is just "a".  However, there exist 6 different overlong encodings of "a" that are technically not valid, but parse just fine in most utf-8 parsers.  (0xC1A1, 0xE081A1, 0xF08081A1, 0xF8808081A1, 0xFC80808081A1, 0xFE8080808081A1).  How many bytes to use for the overlong enocding is specified providing 'size'.
	# 	to_unicode(str, 'utf-8', 'overlong', 2)
	#
	# Many utf-8 parsers also allow invalid overlong encodings, where bits that are unused when encoding a single byte are modified.  Many parsers will ignore these bits, rendering simple string matching to be ineffective for dealing with UTF-8 strings.  There are many more invalid overlong encodings possible for "a".  For example, three encodings are available for an invalid 2 byte encoding of "a". (0xC1E1 0xC161 0xC121).  By specifying "invalid", a random invalid encoding is chosen for the given byte size.
	# 	to_unicode(str, 'utf-8', 'invalid', 2)
	#
	# utf-7 defaults to 'normal' utf-7 encoding
	# utf-8 defaults to 2 byte 'normal' encoding
	# 
	def self.to_unicode(str='', type = 'utf-16le', mode = '', size = '')
		return '' if not str
		case type 
		when 'utf-16le'
			return str.unpack('C*').pack('v*')
		when 'utf-16be'
			return str.unpack('C*').pack('n*')
		when 'utf-32le'
			return str.unpack('C*').pack('V*')
		when 'utf-32be'
			return str.unpack('C*').pack('N*')
		when 'utf-7'
			case mode
			when 'all'
				return str.gsub(/./){ |a|
					out = ''
					if 'a' != '+'
						out = encode_base64(to_unicode(a, 'utf-16be')).gsub(/[=\r\n]/, '')
					end
					'+' + out + '-'
				}
			else
				return str.gsub(/[^\n\r\t\ A-Za-z0-9\'\(\),-.\/\:\?]/){ |a| 
					out = ''
					if a != '+'
						out = encode_base64(to_unicode(a, 'utf-16be')).gsub(/[=\r\n]/, '')
					end
					'+' + out + '-'
				}
			end
		when 'utf-8'
			if size == ''
				size = 2
			end

			if size >= 2 and size <= 7
				string = ''
				str.each_byte { |a|
					if (a < 21 || a > 0x7f) || mode != ''
						# ugh.  turn a single byte into the binary representation of it, in array form
						bin = [a].pack('C').unpack('B8')[0].split(//)

						# even more ugh.
						bin.collect!{|a_| a_.to_i}

						out = Array.new(8 * size, 0)

						0.upto(size - 1) { |i|
							out[i] = 1
							out[i * 8] = 1
						}

						i = 0
						byte = 0
						bin.reverse.each { |bit|
							if i < 6
								mod = (((size * 8) - 1) - byte * 8) - i
								out[mod] = bit
							else 
								byte = byte + 1
								i = 0
								redo
							end
							i = i + 1
						}

						if mode != ''
							case mode
							when 'overlong'
								# do nothing, since we already handle this as above...
							when 'invalid'
								done = 0
								while done == 0
									# the ghetto...
									bits = [7, 8, 15, 16, 23, 24, 31, 32, 41]
									bits.each { |bit|
										bit = (size * 8) - bit
										if bit > 1
											set = rand(2)
											if out[bit] != set
												out[bit] = set
												done = 1
											end
										end
									}
								end
							else
								raise TypeError, 'Invalid mode.  Only "overlong" and "invalid" are acceptable modes for utf-8'
							end
						end
						string << [out.join('')].pack('B*')
					else
						string << [a].pack('C')
					end
				}
				return string
			else 
				raise TypeError, 'invalid utf-8 size'
			end
		when 'uhwtfms' # suggested name from HD :P
			load_codepage()

			string = ''
			# overloading mode as codepage
			if mode == ''
				mode = 1252 # ANSI - Latan 1, default for US installs of MS products
			else
				mode = mode.to_i
			end
			if @@codepage_map_cache[mode].nil?
				raise TypeError, "Invalid codepage #{mode}"
			end
			str.each_byte {|byte|
				char = [byte].pack('C*')
				possible = @@codepage_map_cache[mode]['data'][char]
				if possible.nil?
					raise TypeError, "codepage #{mode} does not provide an encoding for 0x#{char.unpack('H*')[0]}"
				end
				string << possible[ rand(possible.length) ]
			}
			return string
		when 'uhwtfms-half' # suggested name from HD :P
			load_codepage()
			string = ''
			# overloading mode as codepage
			if mode == ''
				mode = 1252 # ANSI - Latan 1, default for US installs of MS products
			else
				mode = mode.to_i
			end
			if mode != 1252
				raise TypeError, "Invalid codepage #{mode}, only 1252 supported for uhwtfms_half"
			end
			str.each_byte {|byte|
				if ((byte >= 33 && byte <= 63) || (byte >= 96 && byte <= 126))
					string << "\xFF" + [byte ^ 32].pack('C')
				elsif (byte >= 64 && byte <= 95)
					string << "\xFF" + [byte ^ 96].pack('C')
				else
					char = [byte].pack('C')
					possible = @@codepage_map_cache[mode]['data'][char]
					if possible.nil?
						raise TypeError, "codepage #{mode} does not provide an encoding for 0x#{char.unpack('H*')[0]}"
					end
					string << possible[ rand(possible.length) ]
				end
			}
			return string
		else 
			raise TypeError, 'invalid utf type'
		end
	end

	# 	
	# Encode a string in a manor useful for HTTP URIs and URI Parameters.  
	#
	def self.uri_encode(str, mode = 'hex-normal')
		return "" if str == nil 

		return str if mode == 'none' # fast track no encoding

		all = /[^\/\\]+/
		normal = /[^a-zA-Z0-9\/\\\.\-]+/
		normal_na = /[a-zA-Z0-9\/\\\.\-]/
		
		case mode
		when 'hex-normal'
			return str.gsub(normal) { |s| Rex::Text.to_hex(s, '%') }
		when 'hex-all'
			return str.gsub(all) { |s| Rex::Text.to_hex(s, '%') }
			when 'hex-random'
				res = ''
				str.each_byte do |c|
					b = c.chr
					res << ((rand(2) == 0) ? 
						b.gsub(all)   { |s| Rex::Text.to_hex(s, '%') } :
						b.gsub(normal){ |s| Rex::Text.to_hex(s, '%') } )
				end
				return res
		when 'u-normal'
			return str.gsub(normal) { |s| Rex::Text.to_hex(Rex::Text.to_unicode(s, 'uhwtfms'), '%u', 2) }
		when 'u-all'
			return str.gsub(all) { |s| Rex::Text.to_hex(Rex::Text.to_unicode(s, 'uhwtfms'), '%u', 2) }
			when 'u-random'
				res = ''
				str.each_byte do |c|
					b = c.chr
					res << ((rand(2) == 0) ? 
						b.gsub(all)   { |s| Rex::Text.to_hex(Rex::Text.to_unicode(s, 'uhwtfms'), '%u', 2) } :
						b.gsub(normal){ |s| Rex::Text.to_hex(Rex::Text.to_unicode(s, 'uhwtfms'), '%u', 2) } )
				end
				return res		
		when 'u-half'
			return str.gsub(all) { |s| Rex::Text.to_hex(Rex::Text.to_unicode(s, 'uhwtfms-half'), '%u', 2) }
		else
			raise TypeError, 'invalid mode'
		end
	end

	# Encode a string in a manor useful for HTTP URIs and URI Parameters.  
	# 
	# a = "javascript".gsub(/./) {|i| "(" + [ Rex::Text.html_encode(i, 'hex'), Rex::Text.html_encode(i, 'int'), Rex::Text.html_encode(i, 'int-wide')].join('|') +')[\s\x00]*' }
	def self.html_encode(str, mode = 'hex')
		case mode
		when 'hex'
			return str.gsub(/./) { |s| Rex::Text.to_hex(s, '&#x') }
		when 'int'
			return str.unpack('C*').collect{ |i| "&#" + i.to_s }.join('')
		when 'int-wide'
			return str.unpack('C*').collect{ |i| "&#" + ("0" * (7 - i.to_s.length)) + i.to_s }.join('')
		else 
			raise TypeError, 'invalid mode'
		end
	end

	# 	
	# Decode a URI encoded string
	#
	def self.uri_decode(str)
		str.gsub(/(%[a-z0-9]{2})/i){ |c| [c[1,2]].pack("H*") }
	end
	
	#
	# Converts a string to random case
	#
	def self.to_rand_case(str)
		buf = str.dup
		0.upto(str.length) do |i|
			buf[i,1] = rand(2) == 0 ? str[i,1].upcase : str[i,1].downcase
		end
		return buf
	end

	#
	# Converts a string a nicely formatted hex dump
	#
	def self.to_hex_dump(str, width=16)
		buf = ''
		idx = 0
		cnt = 0
		snl = false
		lst = 0
		
		while (idx < str.length)
			
			chunk = str[idx, width]
			line  = chunk.unpack("H*")[0].scan(/../).join(" ")
			buf << line	

			if (lst == 0)
				lst = line.length
				buf << " " * 4
			else
				buf << " " * ((lst - line.length) + 4).abs
			end
			
			chunk.unpack("C*").each do |c|
				if (c >	0x1f and c < 0x7f)
					buf << c.chr
				else
					buf << "."
				end
			end
			
			buf << "\n"
		
			idx += width
		end
		
		buf << "\n"
	end
	
	#
	# Converts a hex string to a raw string
	#
	def self.hex_to_raw(str)
		[ str.downcase.gsub(/'/,'').gsub(/\\?x([a-f0-9][a-f0-9])/, '\1') ].pack("H*")
	end

	#
	# Wraps text at a given column using a supplied indention
	#
	def self.wordwrap(str, indent = 0, col = DefaultWrap, append = '', prepend = '')
		return str.gsub(/.{1,#{col - indent}}(?:\s|\Z)/){
			( (" " * indent) + prepend + $& + append + 5.chr).gsub(/\n\005/,"\n").gsub(/\005/,"\n")}
	end

	#
	# Converts a string to a hex version with wrapping support
	#
	def self.hexify(str, col = DefaultWrap, line_start = '', line_end = '', buf_start = '', buf_end = '')
		output   = buf_start
		cur      = 0
		count    = 0
		new_line = true

		# Go through each byte in the string
		str.each_byte { |byte|
			count  += 1
			append  = ''

			# If this is a new line, prepend with the
			# line start text
			if (new_line == true)
				append   << line_start
				new_line  = false
			end

			# Append the hexified version of the byte
			append << sprintf("\\x%.2x", byte)
			cur    += append.length

			# If we're about to hit the column or have gone past it,
			# time to finish up this line
			if ((cur + line_end.length >= col) or (cur + buf_end.length  >= col))
				new_line  = true
				cur       = 0

				# If this is the last byte, use the buf_end instead of
				# line_end
				if (count == str.length)
					append << buf_end + "\n"
				else
					append << line_end + "\n"
				end
			end

			output << append
		}

		# If we were in the middle of a line, finish the buffer at this point
		if (new_line == false)
			output << buf_end + "\n"
		end	

		return output
	end

	##
	#
	# Transforms
	#
	##

	#
	# Base64 encoder
	#
	def self.encode_base64(str, delim='')
		[str].pack("m").gsub(/\s+/, delim)
	end

	#
	# Base64 decoder
	#
	def self.decode_base64(str)
		str.unpack("m")[0]
	end

	#
	# Raw MD5 digest of the supplied string
	#
	def self.md5_raw(str)
		Digest::MD5.digest(str)	
	end

	#
	# Hexidecimal MD5 digest of the supplied string
	#
	def self.md5(str)
		Digest::MD5.hexdigest(str)
	end


	##
	#
	# Generators
	#
	##


	# Generates a random character.
	def self.rand_char(bad, chars = AllChars)
		rand_text(1, bad, chars)	
	end
	
	# Base text generator method
	def self.rand_base(len, bad, *foo)
		# Remove restricted characters
		(bad || '').split('').each { |c| foo.delete(c) }

		# Return nil if all bytes are restricted
		return nil if foo.length == 0
	
		buff = ""
	
		# Generate a buffer from the remaining bytes
		if foo.length >= 256
			len.times { buff << Kernel.rand(256) }
		else 
			len.times { buff << foo[ rand(foo.length) ] }
		end

		return buff
	end

	# Generate random bytes of data
	def self.rand_text(len, bad='', chars = AllChars)
		foo = chars.split('')
		rand_base(len, bad, *foo)
	end

	# Generate random bytes of alpha data
	def self.rand_text_alpha(len, bad='')
		foo = []
		foo += ('A' .. 'Z').to_a
		foo += ('a' .. 'z').to_a
		rand_base(len, bad, *foo )
	end

	# Generate random bytes of lowercase alpha data
	def self.rand_text_alpha_lower(len, bad='')
		rand_base(len, bad, *('a' .. 'z').to_a)
	end

	# Generate random bytes of uppercase alpha data
	def self.rand_text_alpha_upper(len, bad='')
		rand_base(len, bad, *('A' .. 'Z').to_a)
	end

	# Generate random bytes of alphanumeric data
	def self.rand_text_alphanumeric(len, bad='')
		foo = []
		foo += ('A' .. 'Z').to_a
		foo += ('a' .. 'z').to_a
		foo += ('0' .. '9').to_a
		rand_base(len, bad, *foo )
	end

	# Generate random bytes of alphanumeric hex.
	def self.rand_text_hex(len, bad='')
		foo = []
		foo += ('0' .. '9').to_a
		foo += ('a' .. 'f').to_a
		rand_base(len, bad, *foo)
	end

	# Generate random bytes of numeric data
	def self.rand_text_numeric(len, bad='')
		foo = ('0' .. '9').to_a
		rand_base(len, bad, *foo )
	end
	
	# Generate random bytes of english-like data
	def self.rand_text_english(len, bad='')
		foo = []
		foo += (0x21 .. 0x7e).map{ |c| c.chr }
		rand_base(len, bad, *foo )
	end
	
	# Generate random bytes of high ascii data
	def self.rand_text_highascii(len, bad='')
		foo = []
		foo += (0x80 .. 0xff).map{ |c| c.chr }
		rand_base(len, bad, *foo )
	end

	#
	# Creates a pattern that can be used for offset calculation purposes.  This
	# routine is capable of generating patterns using a supplied set and a
	# supplied number of identifiable characters (slots).  The supplied sets
	# should not contain any duplicate characters or the logic will fail.
	#
	def self.pattern_create(length, sets = [ UpperAlpha, LowerAlpha, Numerals ])
		buf = ''
		idx = 0
		offsets = []

		sets.length.times { offsets << 0 }

		until buf.length >= length
			begin
				buf << converge_sets(sets, 0, offsets, length)
			rescue RuntimeError
				break
			end
		end
		
		# Maximum permutations reached, but we need more data
		if (buf.length < length)
			buf = buf * (length / buf.length.to_f).ceil
		end

		buf[0,length]
	end

	#
	# Calculate the offset to a pattern
	#
	def self.pattern_offset(pattern, value, start=0)
		if (value.kind_of?(String))
			pattern.index(value, start)
		elsif (value.kind_of?(Fixnum) or value.kind_of?(Bignum))
			pattern.index([ value ].pack('V'), start)
		else
			raise ::ArgumentError, "Invalid class for value: #{value.class}"
		end
	end

	#
	# Compresses a string, eliminating all superfluous whitespace before and
	# after lines and eliminating all lines.
	#
	def self.compress(str)
		str.gsub(/\n/m, ' ').gsub(/\s+/, ' ').gsub(/^\s+/, '').gsub(/\s+$/, '')
	end

	#
	# Randomize the whitespace in a string
	#
	def self.randomize_space(str)
		str.gsub(/\s+/) { |s|
			len = rand(50)+2
			set = "\x09\x20\x0d\x0a"
			buf = ''
			while (buf.length < len)
				buf << set[rand(set.length),1]
			end
			
			buf
		}
	end

	# Returns true if zlib can be used.
	def self.zlib_present?
		begin
			temp = Zlib
			return true
		rescue
			return false
		end
	end
	
	# backwards compat for just a bit...
	def self.gzip_present?
		self.zlib_present?
	end

	#
	# Compresses a string using zlib
	#
	def self.zlib_deflate(str, level = Zlib::BEST_COMPRESSION)
		if self.zlib_present?
			z = Zlib::Deflate.new(level)
			dst = z.deflate(str, Zlib::FINISH)
			z.close
			return dst
		else			
			raise RuntimeError, "Gzip support is not present."
		end
	end

	#
	# Uncompresses a string using zlib
	#
	def self.zlib_inflate(str)
		if(self.zlib_present?)
			zstream = Zlib::Inflate.new
			buf = zstream.inflate(str)
			zstream.finish
			zstream.close
			return buf
		else
			raise RuntimeError, "Gzip support is not present."
		end
	end

	#
	# Compresses a string using gzip
	#
	def self.gzip(str, level = 9)
		raise RuntimeError, "Gzip support is not present." if (!zlib_present?)
		raise RuntimeError, "Invalid gzip compression level" if (level < 1 or level > 9)

		s = ""
		gz = Zlib::GzipWriter.new(StringIO.new(s), level)
		gz << str
		gz.close
		return s
	end
	
	#
	# Uncompresses a string using gzip
	#
	def self.ungzip(str)
		raise RuntimeError, "Gzip support is not present." if (!zlib_present?)

		s = ""
		gz = Zlib::GzipReader.new(StringIO.new(str))
		s << gz.read
		gz.close
		return s
	end
	
	#
	# Return the index of the first badchar in data, otherwise return
	# nil if there wasn't any badchar occurences.
	#
	def self.badchar_index(data, badchars = '')
		badchars.unpack("C*").each { |badchar|
			pos = data.index(badchar.chr)
			return pos if pos
		}
		return nil
	end

	#
	# This method removes bad characters from a string.
	#
	def self.remove_badchars(data, badchars = '')
		data.delete(badchars)
	end

	#
	# This method returns all chars but the supplied set
	#
	def self.charset_exclude(keepers)
		[*(0..255)].pack('C*').delete(keepers)
	end

	#
	#  Shuffles a byte stream
	#
	def self.shuffle_s(str)
		shuffle_a(str.unpack("C*")).pack("C*")
	end

	#
	# Performs a Fisher-Yates shuffle on an array
	#
	def self.shuffle_a(arr)
		len = arr.length
		max = len - 1
		cyc = [* (0..max) ]
		for d in cyc
			e = rand(d+1)
			next if e == d
			f = arr[d];
			g = arr[e];
			arr[d] = g;
			arr[e] = f;
		end
		return arr
	end

	# Permute the case of a word
	def self.permute_case(word, idx=0)
		res = []

		if( (UpperAlpha+LowerAlpha).index(word[idx,1]))

			word_ucase = word.dup
			word_ucase[idx, 1] = word[idx, 1].upcase
			
			word_lcase = word.dup
			word_lcase[idx, 1] = word[idx, 1].downcase
	
			if (idx == word.length)
				return [word]
			else
				res << permute_case(word_ucase, idx+1)
				res << permute_case(word_lcase, idx+1)
			end
		else
			res << permute_case(word, idx+1)
		end
		
		res.flatten
	end

	# Generate a random hostname
	def self.rand_hostname
		host = []
		(rand(5) + 1).times {
			host.push(Rex::Text.rand_text_alphanumeric(rand(10) + 1))
		}
		d = ['com', 'net', 'org', 'gov']
		host.push(d[rand(d.size)])
		host.join('.').downcase
	end

	# Generate a state
	def self.rand_state()
		States[rand(States.size)]
	end


	#
	# Calculate the ROR13 hash of a given string
	#
	def self.ror13_hash(name)
		hash = 0
		name.unpack("C*").each {|c| hash = ror(hash, 13); hash += c }
		hash
	end

	#
	# Rotate a 32-bit value to the right by cnt bits
	#
	def self.ror(val, cnt)
		bits = [val].pack("N").unpack("B32")[0].split(//)
		1.upto(cnt) do |c|
			bits.unshift( bits.pop )
		end
		[bits.join].pack("B32").unpack("N")[0]
	end
	
	#
	# Rotate a 32-bit value to the left by cnt bits
	#
	def self.rol(val, cnt)
		bits = [val].pack("N").unpack("B32")[0].split(//)
		1.upto(cnt) do |c|
			bits.push( bits.shift )
		end
		[bits.join].pack("B32").unpack("N")[0]
	end


protected

	def self.converge_sets(sets, idx, offsets, length) # :nodoc:
		buf = sets[idx][offsets[idx]].chr

		# If there are more sets after use, converage with them.
		if (sets[idx + 1])
			buf << converge_sets(sets, idx + 1, offsets, length)
		else
			# Increment the current set offset as well as previous ones if we
			# wrap back to zero.
			while (idx >= 0 and ((offsets[idx] = (offsets[idx] + 1) % sets[idx].length)) == 0)
				idx -= 1
			end

			# If we reached the point where the idx fell below zero, then that
			# means we've reached the maximum threshold for permutations.
			if (idx < 0)
				raise RuntimeError, "Maximum permutations reached"
			end
		end

		buf
	end
	
	def self.load_codepage()
		return if (!@@codepage_map_cache.nil?)
		file = File.join(File.dirname(__FILE__),'codepage.map')
		page = ''
		name = ''
		map = {}
		File.open(file).each { |line|
			next if line =~ /^#/
			next if line =~ /^\s*$/
			data = line.split
			if data[1] =~ /^\(/
				page = data.shift.to_i
				name = data.join(' ').sub(/^\(/,'').sub(/\)$/,'')
				map[page] = {}
				map[page]['name'] = name
				map[page]['data'] = {}
			else
				data.each { |entry|
					wide, char = entry.split(':')
					char = [char].pack('H*')
					wide = [wide].pack('H*')
					if map[page]['data'][char].nil?
						map[page]['data'][char] = [wide]
					else
						map[page]['data'][char].push(wide)
					end
				}
			end
		}
		@@codepage_map_cache = map
	end

end
end
