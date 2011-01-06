module MsfTest
module WindowsMeterpreterSpecs

	## This file is intended to be used in conjunction with a harness, 
	## such as meterpreter_win32_spec.rb

	def self.included(base)
        	base.class_eval do

			it "should not error when uploading a file to a windows box" do
				upload_success_strings = [ 	'uploading',
								'uploaded' ]	

				## create a file to upload
				filename = "/tmp/whatever"
				if File.exist?(filename)
					FileUtils.rm(filename)
				end
				hlp_string_to_file("owned!", filename)

				## run the upload / quit commands
				hlp_run_command_check_output("upload","upload #{filename} C:\\", upload_success_strings)
				#hlp_run_command_check_output("quit","quit")

				## clean up
				FileUtils.rm(filename)
			end
						
		end
	end

end
end
