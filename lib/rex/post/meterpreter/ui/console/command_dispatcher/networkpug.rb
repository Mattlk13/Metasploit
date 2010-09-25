require 'rex/post/meterpreter'

module Rex
module Post
module Meterpreter
module Ui

# Rex::Ui::Text::IrbShell.new(binding).run

class Console::CommandDispatcher::NetworkPug

	Klass = Console::CommandDispatcher::NetworkPug

	include Console::CommandDispatcher

	@@options = Rex::Parser::Arguments.new(
		"-i" => [ true, "Interface on remote machine to listen on" ],
		"-f" => [ true, "Additional pcap filtering mechanism" ],
		"-v" => [ false, "Virtual NIC (packets only for your TAP dev locally)" ]
	)

	def initialize(shell)
		super
	end

	#
	# List of supported commands.
	#
	def commands
		{
			"networkpug_start" => "Start slinging packets between hosts",
			"networkpug_stop"  => "Stop slinging packets between hosts",
		}
	end

	def setup_tapdev
		# XXX, look at how to use windows equivilient and include

		tapdev = ::File.open("/dev/net/tun", "wb+")

		0.upto(16) { |idx| 
			name = "npug#{idx}"

			ifreq = [ name, 0x1000 | 0x02, "" ].pack("a16va14")

			begin
				tapdev.ioctl(0x400454ca, ifreq)		# is there a better way than hex constant
			rescue Errno::EBUSY
				next
			end
			
			ifreq = [ name ].pack("a32")

			tapdev.ioctl(0x8927, ifreq)

			# print_line(Rex::Text.hexify(ifreq))

			mac = sprintf("%02x:%02x:%02x:%02x:%02x:%02x", ifreq[18], ifreq[19], ifreq[20], ifreq[21], ifreq[22], ifreq[23])

			return tapdev, name, mac
		}
		
		tapdev.close()
		return nil, nil, nil
	end

	def proxy_packets(tapdev, channel)
		while 1
			# Ghetto :\

			sd = Rex::ThreadSafe.select([ channel.lsock, tapdev ], nil, nil)

			sd[0].each { |s|
				if(s == channel.lsock)	# Packet from remote host to local TAP dev
					len = channel.lsock.read(2)
					len = len.unpack('n')[0]

					# print_line("Got #{len} bytes from remote host's network")
					
					if(len > 1514 or len == 0)
						tapdev.close()
						print_line("length is invalid .. #{len} ?, de-synchronized ? ")
					end

					packet = channel.lsock.read(len)

					# print_line("remote from remote host:\n" + Rex::Text.hexify(packet))

					tapdev.syswrite(packet)

				elsif(s == tapdev) 
					# Packet from tapdev to remote host network

					packet = tapdev.sysread(1514)

					# print_line("packet to remote host:\n" + Rex::Text.hexify(packet))

					channel.write(packet)
				end
			} if(sd)
		end
	end


	def cmd_networkpug_start(*args)
		# PKS - I suck at ruby ;\

		virtual_nic = false
		filter = nil
		interface = nil

		if(args.length == 0)
			args.unshift("-h")
		end

		@@options.parse(args) { |opt, idx, val| 

			# print_line("before: #{opt} #{idx} #{val} || virtual nic: #{virtual_nic}, filter: #{filter}, interface: #{interface}")
			case opt
				when "-v"
					virtual_nic = true

				when "-f"
					filter = val

				when "-i"
					interface = val

				when "-h"
					print_error("Usage: networkpug_start -i interface [options]")
					print_error("")
					print_error(@@options.usage)
			end
			# print_line("after: #{opt} #{idx} #{val} || virtual nic: #{virtual_nic}, filter: #{filter}, interface: #{interface}")

		}

		if (interface == nil)
			print_error("Usage: networkpug_start -i interface [options]")
			print_error("")
			print_error(@@options.usage)
			return
		end

		tapdev, tapname, mac = setup_tapdev

		if(tapdev == nil)
			print_status("Failed to create tapdev")
			return
		end

		# PKS, we should implement multiple filter strings and let the 
		# remote host build it properly.
		# not (our conn) and (virtual nic filter) and (custom filter) 

		# print_line("before virtual, filter is #{filter}")

		if(filter == nil and virtual_nic == true)
			filter = "ether host #{mac}"
		elsif(filter != nil and virtual_nic == true)
			filter += " and ether host #{mac}"
			print_line("Adjusted filter is #{filter}")
		end

		# print_line("after virtual, filter is #{filter}")

		print_line("#{tapname} created with a hwaddr of #{mac}, ctrl-c when done")

		begin
			response, channel = client.networkpug.networkpug_start(interface, filter)

			if(not channel)
				print_line("No channel? bailing")
				return
			end


			print_line("Forwarding packets between #{tapname} and remote host")
			proxy_packets(tapdev, channel)
		ensure
			tapdev.close()
			print_line("don't forget to networkpug_stop remote host as well")
			
		end

		return true
	end
	
	def cmd_networkpug_stop(*args)
		interface = args[0]
		if (interface == nil)
			print_error("Usage: networkpug_stop [interface]")
			return
		end
		
		client.networkpug.networkpug_stop(interface)
		print_status("Packet slinging stopped on #{interface}")
		return true
	end
	
	def name
		"NetworkPug"
	end

end

end
end
end
end