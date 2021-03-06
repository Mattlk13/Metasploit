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


class Metasploit3 < Msf::Auxiliary

	# Exploit mixins should be called first
	include Msf::Exploit::Remote::HttpClient
	include Msf::Auxiliary::WMAPScanServer
	# Scanner mixin should be near last
	include Msf::Auxiliary::Scanner
	include Msf::Auxiliary::Report

	def initialize
		super(
			'Name'        => 'HTTP Robots.txt Content Scanner',
			'Version'     => '$Revision$',
			'Description' => 'Detect robots.txt files and analize its content',
			'Author'       => ['et'],
			'License'     => MSF_LICENSE
		)

		register_options(
			[
				OptString.new('PATH', [ true,  "The test path to find robots.txt file", '/']),
				OptBool.new('VERBOSE', [ true,  "Display verbose messages", true])

			], self.class)

	end

	def run_host(target_host)

		tpath = datastore['PATH']
		if tpath[-1,1] != '/'
			tpath += '/'
		end

		begin
			turl = tpath+'robots.txt'

			res = send_request_raw({
				'uri'     => turl,
				'method'  => 'GET',
				'version' => '1.0',
			}, 10)


			if not res
				print_error("[#{target_host}] #{tpath}robots.txt - No response")
				return
			end

			if not res.body.include?("llow:")
				print_status("[#{target_host}] #{tpath}robots.txt - Doesn't contain \"llow:\"") if datastore['VERBOSE']
				print_status(res.body.inspect) if datastore['DEBUG']
				return
			end

			print_status("[#{target_host}] #{tpath}robots.txt found")

			# short url regex
			aregex = /llow:[ ]{0,2}(.*?)$/i

			result = res.body.scan(aregex).flatten.map{ |s| s.strip }.uniq

			print_status("[#{target_host}] #{tpath}robots.txt - #{result.join(', ')}") if datastore['VERBOSE']
			result.each do |u|
				report_note(
					:host	=> target_host,
					:port	=> rport,
					:proto => 'tcp',
					:sname	=> (ssl ? 'https' : 'http'),
					:type	=> 'ROBOTS_TXT',
					:data	=> "#{u}",
					:update => :unique_data
				)
			end

		rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout
		rescue ::Timeout::Error, ::Errno::EPIPE
		end
	end
end

