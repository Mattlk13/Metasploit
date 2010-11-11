#!/usr/bin/env ruby
#
# $Id$
#
# Check (recursively) for style compliance violations and other
# tree inconsistencies.
#
# by jduck
#

##
#
# Supporting sub-routines
#
##

def show_count(f, txt, num)
	puts "%s ... %s: %u" % [f, txt, num] if num > 0
end

def show_missing(f, txt, val)
	puts '%s ... %s' % [f, txt] if not val
end


def check_single_file(dparts, fparts, f_rel)
	f = (dparts + fparts).join('/')
	#puts f

	# blacklisted files..
	#?

	# check svn existence
	svn_parts = fparts[0, fparts.length - 1] + [ '.svn', 'text-base' ]
	svn_parts << fparts[-1, 1].first + '.svn-base'
	svn_path = svn_parts.join('/')
	if not File.file?(svn_path)
		show_missing(f, 'not in SVN!', false)
	else
		# check svn properties
		svn_parts = fparts[0, fparts.length - 1] + [ '.svn', 'prop-base' ]
		svn_parts << fparts[-1, 1].first + '.svn-base'
		svn_path = svn_parts.join('/')
		props = File.open(svn_path, 'rb').read rescue nil
		if props
			kw = false
			exec = false
			mime = false
			props.each_line { |ln|
				kw = true if ln =~ /svn:keywords/
				exec = true if ln =~ /svn:executable/
				mime = true if ln =~ /svn:mime-type/
			}

			show_missing(f, 'missing svn:keywords', kw)
			show_missing(f, 'is executable!', (not exec))
			show_missing(f, 'has mime-type property!', (not mime))
		else
			show_missing(f, 'missing svn properties', props)
		end
	end

	# check various properties based on content
	content = File.open(f_rel, "rb").read

	spaces = 0
	bi = []
	cr = 0
	has_rev = false
	has_id = false
	url_ok = true
	nbo = 0 # non-bin open

	in_comment = false
	idx = 0
	content.each_line { |ln|
		idx += 1

		# block comment awareness
		if ln =~ /^=end$/
			in_comment = false
			next
		end
		in_comment = true if ln =~ /^=begin$/
		next if in_comment

		spaces += 1 if ln =~ / $/
		if (ln.length > 1) and (ln =~ /^([\t ]*)/) and ($1.include?(' '))
			bi << [ idx, ln ]
		end
		cr += 1 if ln =~ /\r$/
		has_id = true if ln =~ /\$Id:.*\$/
		has_rev = true if ln =~ /\$Revision:.*\$/
		url_ok = false if ln =~ /\.com\/projects\/Framework/
		if ln =~ /File\.open/ and ln =~ /[\"\'][arw]/
			if not ln =~ /[\"\'][wra]b\+?[\"\']/
				nbo += 1
			end
		end
	}

	# report information for this file
	show_count(f, 'spaces at EOL', spaces)
	if bi.length > 0
		puts '%s ... bad indent: %u' % [f, bi.length]
		bi.each { |el|
			el[1] = el[1].inspect
			puts '  %8d: %s' % el
		}
	end

	show_count(f, 'carriage return EOL', cr)
	show_missing(f, 'missing $'+'Id: $', has_id)
	show_missing(f, 'missing $'+'Revision: $', has_rev)
	show_missing(f, 'incorrect URL to framework site', url_ok)
	show_count(f, 'File.open without binary mode', nbo)
end



##
#
# Main program
#
##

dirs = ARGV

if dirs.length < 1
	$stderr.puts "usage: #{File.basename(__FILE__)} <directory or file>"
	exit(1)
end

dirs.each { |dir|
	# process all args

	f = nil
	old_dir = nil

	if dir
		if File.file?(dir)
			# whoa, a single file!
			f = File.basename(dir)
			dir = File.dirname(dir)
		end

		old_dir = Dir.getwd
		Dir.chdir(dir)
		dparts = dir.split('/')
	else
		dparts = []
	end

	# Only one file?
	if f
		check_single_file(dparts, [ f ], f)
	else
		# Do a recursive check of the specified directory
		Dir.glob('**/*.rb') { |f|
			check_single_file(dparts, f.split('/'), f)
		}
	end

	Dir.chdir(old_dir)
}
