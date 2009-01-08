#!/usr/bin/env ruby
require 'ftools'
#
#Meterpreter script for ping sweeps on Windows 2003, Windows Vista
#Windows 2008 and Windows XP targets using native windows commands.
#Provided by Carlos Perez at carlos_perez[at]darkoperator.com
#Verion: 0.1.1
#Note:
################## Variable Declarations ##################
@@exec_opts = Rex::Parser::Arguments.new(
  "-h"  => [ false,  "Help menu."],
  "-r"  => [ true,  "The target address range or CIDR identifier"],
  "-ps" => [ false,  "To Perform Ping Sweeo on IP Range"],
  "-rl" => [ false,  "To Perform DNS Reverse Lookup on IP Range"],
  "-fl" => [ false,  "To Perform DNS Fordward Lookup on host list and domain"],
  "-hl" => [ true,  "File with Host List for DNS Fordward Lookup"],
  "-d"  => [ true,  "Domain Name for DNS Fordward Lookup"],
  "-st" => [ false,  "To Perform DNS lookup of MX, NS and SOA records for a domain"]

)
session = client
host,port = session.tunnel_peer.split(':')

# Create Filename info to be appended to downloaded files
filenameinfo = "_" + ::Time.now.strftime("%Y%m%d.%M%S")+sprintf("%.5d",rand(100000))

# Create a directory for the logs
logs = ::File.join(Msf::Config.config_directory, 'logs', 'netenum', host)

# Create the log directory
::FileUtils.mkdir_p(logs)

#logfile name
dest = logs + "/" + host + filenameinfo

#-------------------------------------------------------------------------------
# Function for performing regular lookup of MX and NS records
def stdlookup(session,domain,dest)
	dest = dest + "-general-record-lookup.txt"
	print_status("Getting MX and NS Records for Domain #{domain}")
	filewrt(dest,"MX and NS Records for Domain #{domain}")
	mxout = []
	results = []
	garbage = []
	begin
		r = session.sys.process.execute("nslookup -query=mx #{domain}", nil, {'Hidden' => true, 'Channelized' => true})
		while(d = r.channel.read)
			mxout << d
		end
		r.channel.close
		r.close
		results = mxout.to_s.split(/\n/)
		results.each do |rec|
			if rec =~ /(Name:)/ or rec =~ /(Address:)/ or rec =~ /(Server:)/
				garbage << rec
			else
				print_status("\t#{rec}")
				filewrt(dest,"#{rec}")
			end
		end

	rescue ::Exception => e
    		print_status("The following Error was encountered: #{e.class} #{e}")
	end
end
#-------------------------------------------------------------------------------
# Function for writing results of other functions to a file
def filewrt(file2wrt, data2wrt)
	output = ::File.open(file2wrt, "a")
	data2wrt.each do |d|
		output.puts(d)
	end
	output.close
end
#-------------------------------------------------------------------------------
# Function for Executing Reverse lookups
def reverselookup(session,iprange,dest)
	dest = dest + "-DNS-reverse-lookup.txt"
	print_status("Performing DNS Reverse Lookup for IP range #{iprange}")
	filewrt(dest,"DNS Reverse Lookup for IP range #{iprange}")
	iplst =[]
	i, a = 0, []
	begin
		ipadd = Rex::Socket::RangeWalker.new(iprange)
				numip = ipadd.num_ips
				while (iplst.length < numip)
					ipa = ipadd.next_ip
		      			if (not ipa)
		        			break
		      			end
					iplst << ipa
				end
		begin
		    iplst.each do |ip|
		      if i < 10
		        a.push(::Thread.new {
			  	r = session.sys.process.execute("nslookup #{ip}", nil, {'Hidden' => true, 'Channelized' => true})
	        		while(d = r.channel.read)
	         			if d =~ /(Name)/
	            				d.scan(/Name:\s*\S*\s/) do |n|
	              				hostname = n.split(":    ")
	              				print_status "\t #{ip} is #{hostname[1].chomp("\n")}"
	              				filewrt(dest,"#{ip} is #{hostname[1].chomp("\n")}")
	            			end
	            			break

	          		end

		        	end

		        	r.channel.close
		        	r.close

		          })
		        i += 1
		      else
		        sleep(0.05) and a.delete_if {|x| not x.alive?} while not a.empty?
		        i = 0
		      end
		    end
		    a.delete_if {|x| not x.alive?} while not a.empty?
		  end
	rescue ::Exception => e
    		print_status("The following Error was encountered: #{e.class} #{e}")

	end
end
#-------------------------------------------------------------------------------
#Function for Executing Fordward Lookups
def frwdlp(session,hostlst,domain,dest)
	dest = dest + "-DNS-fordward-lookup.txt"
	print_status("Performing DNS Fordward Lookup for hosts in #{hostlst} for domain #{domain}")
	filewrt(dest,"DNS Fordward Lookup for hosts in #{hostlst} for domain #{domain}")
	result = []
	threads = []
	tmpout = []
	begin
	if ::File.exists?(hostlst)
		::File.open(hostlst).each {|line|
    			threads << ::Thread.new(line) { |h|
    			#print_status("checking #{h.chomp}")
		  	r = session.sys.process.execute("nslookup #{h.chomp}.#{domain}", nil, {'Hidden' => true, 'Channelized' => true})
       		 	while(d = r.channel.read)
          			if d =~ /(Name)/
            				d.scan(/Name:\s*\S*\s*Address\w*:\s*.*?.*?.*/) do |n|
            				tmpout << n.split
            			end
           			break
          		end
        end
        
        r.channel.close
        r.close
			}
		}
	threads.each { |aThread|  aThread.join }
	tmpout.uniq.each do |t|
        	print_status ("\t#{t.to_s.sub(/Address\w*:/, "\t")}")
        	filewrt(dest,"#{t.to_s.sub(/Address\w*:/, "\t")}")
        end

	else
		print_status("File #{hostlst}does not exists!")
		exit
	end
	rescue ::Exception => e
    		print_status("The following Error was encountered: #{e.class} #{e}")
	end
end
#-------------------------------------------------------------------------------
#Function for Executing Ping Sweep
def pingsweep(session,iprange,dest)
	dest = dest + "-pingsweep.txt"
	print_status("Performing ping sweep for IP range #{iprange}")
	filewrt(dest,"Ping sweep for IP range #{iprange}")
	iplst = []
	begin
		i, a = 0, []
		ipadd = Rex::Socket::RangeWalker.new(iprange)
		numip = ipadd.num_ips
		while (iplst.length < numip)
			ipa = ipadd.next_ip
      			if (not ipa)
        			break
      			end
			iplst << ipa
		end
		begin
		    iplst.each do |ip|
		      if i < 10
		        a.push(::Thread.new {
		          r = session.sys.process.execute("ping #{ip} -n 1", nil, {'Hidden' => true, 'Channelized' => true})
		        	while(d = r.channel.read)
		          		if d =~ /(Reply)/
		            			print_status "\t#{ip} host found"
		            			filewrt(dest,"#{ip} host found")
		            			r.channel.close
		          		end
		        	end
		        	r.channel.close
		        	r.close

		          })
		        i += 1
		      else
		        sleep(0.05) and a.delete_if {|x| not x.alive?} while not a.empty?
		        i = 0
		      end
		    end
		    a.delete_if {|x| not x.alive?} while not a.empty?
		  end
	rescue ::Exception => e
    		print_status("The following Error was encountered: #{e.class} #{e}")

	end
end
#-------------------------------------------------------------------------------
#Function to print message during run
def message(dest)
	print_status "Network Enumerator Meterpreter Script "
	print_status "Log file being saved in #{dest}"
end
################## MAIN ##################

# Variables for Options
stdlkp = nil
range = nil
pngsp = nil
rvrslkp = nil
frdlkp = nil
dom = nil
hostlist = nil
helpcall = nil
# Parsing of Options
@@exec_opts.parse(args) { |opt, idx, val|
	case opt

  when "-rl"
    rvrslkp = 1
  when "-fl"
    frdlkp = 1
  when "-ps"
    pngsp = 1
  when "-st"
  	stdlkp = 1
  when "-d"
    dom = val
  when "-hl"
    hostlist = val
  when "-r"
    range = val
  when "-h"
    print(
      "Network Enumerator Meterpreter Script\n" +
      "Usage:\n" +
        @@exec_opts.usage
    )
    helpcall = 1
  end

}

if range != nil && pngsp == 1
	message(logs)
	pingsweep(session,range,dest)
elsif range != nil && rvrslkp == 1
	message(logs)
	reverselookup(session,range,dest)
elsif dom != nil && hostlist!= nil && frdlkp == 1
	message(logs)
	frwdlp(session,hostlist,dom,dest)
elsif dom != nil && stdlkp == 1
	stdlookup(session,dom,dest)
elsif helpcall == nil
	print(
    	"Network Enumerator Meterpreter Script\n" +
    	"Usage: \n" +
      @@exec_opts.usage)
end
