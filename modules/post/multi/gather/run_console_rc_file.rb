##
# $Id$
##

##
# ## This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'rex'

class Metasploit3 < Msf::Post



	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Run Console Resource File',
				'Description'   => %q{ This module will read console commands from a resource file and
					execute the commands in the speciffied Meterpreter session.},
				'License'       => MSF_LICENSE,
				'Author'        => [ 'Carlos Perez <carlos_perez[at]darkoperator.com>'],
				'Version'       => '$Revision$',
				'Platform'      => [ 'windows' ],
				'SessionTypes'  => [ 'meterpreter' ]
			))
		register_options(
			[

				OptString.new('RESOURCE', [true, 'Full path to resource file to read commands from.', nil]),


			], self.class)
	end

	# Run Method for when run command is issued
	def run
		print_status("Running module against #{sysinfo['Computer']}")
		if not ::File.exists?(datastore['RESOURCE'])
                        raise "Resource File does not exists!"
                else
                        ::File.open(datastore['RESOURCE'], "r").each_line do |cmd|
                                next if cmd.strip.length < 1
				next if cmd[0,1] == "#"
				begin
					print_status "Running command #{cmd.chomp}"
					session.console.run_single(cmd.chomp)
				rescue ::Exception => e
					print_status("Error Running Command #{cmd.chomp}: #{e.class} #{e}")
				end
                        end
                end
	end
end