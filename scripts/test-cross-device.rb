# Runs both Flutter apps against each other. ADB reverse carries coordination
# only; all test payloads travel through the real tailcat tunnels.
require 'socket'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'shellwords'
require 'timeout'
$stdout.sync=true
adb=ENV.fetch('ADB','adb')
device=ARGV.fetch(0){abort 'Usage: ruby scripts/test-cross-device.rb <adb-device-id>'}
root=File.expand_path('..',__dir__)
copy=Dir.mktmpdir('tailtap-cross-android-')
system('rsync','-a','--exclude=.git','--exclude=build','--exclude=.dart_tool','--exclude=android/.gradle',"#{root}/",copy) or abort 'Could not prepare isolated Android build'
control=TCPServer.new('127.0.0.1',0)
target=TCPServer.new('127.0.0.1',0)
port=control.addr[1]
values={'host-target'=>{'port'=>target.addr[1]}}
termux_input=nil
termux_wait=nil
if ENV['TERMUX_HOST']
 code='const http=require("node:http");const server=http.createServer((request,response)=>response.end("TAILTAP_ANDROID_TARGET"));server.listen(0,"127.0.0.1",()=>console.log(JSON.stringify({port:server.address().port})));process.stdin.resume();process.stdin.on("end",()=>server.close(()=>process.exit(0)));'
 termux_input,termux_output,termux_error,termux_wait=Open3.popen3('ssh','-o','BatchMode=yes',ENV['TERMUX_HOST'],"node -e #{Shellwords.escape(code)}")
 values['termux-target']=JSON.parse(Timeout.timeout(10){termux_output.gets})
 Thread.new{termux_error.read}
 puts 'Termux independent HTTP target is ready'
end
mu=Mutex.new
service=lambda do |server, target_only|
 Thread.new do
  loop do
   socket=server.accept
   Thread.new(socket) do |s|
    begin
     request=s.gets
     next unless request
     method,path=request.split(' ')
     headers={}
     while (line=s.gets) && line!="\r\n";k,v=line.split(':',2);headers[k.downcase]=v.strip if v;end
     if target_only
      body='TAILTAP_MAC_TARGET'
     else
      key=path.delete_prefix('/')
      if method=='POST'
       data=JSON.parse(s.read(headers.fetch('content-length','0').to_i))
       mu.synchronize{values[key]=data}
       puts "PASS: #{key}" if key.end_with?('-pass')
      end
      body=JSON.generate(mu.synchronize{values[key]||{}})
     end
     s.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    rescue IOError,JSON::ParserError,SystemCallError
    ensure;s.close;end
   end
  end
 rescue IOError
 end
end
threads=[service.call(control,false),service.call(target,true)]
system(adb,'-s',device,'reverse',"tcp:#{port}","tcp:#{port}") or abort 'ADB coordinator setup failed'
statuses=[]
processes=[]
begin
 jobs=[['Mac',root,'macos'],['Android',copy,device]].map do |name,dir,id|
  Thread.new do
   Open3.popen2e('flutter','test','integration_test/cross_device_test.dart','-d',id,'--reporter','expanded',"--dart-define=TAILTAP_COORDINATOR_PORT=#{port}",chdir:dir) do |stdin,out,wait|
    mu.synchronize{processes << wait.pid}
    stdin.close
    out.each_line{|line|puts "#{name}: #{line}"}
    status=wait.value.exitstatus
    statuses<<status
    if status!=0
      mu.synchronize{processes.dup}.each{|pid|next if pid==wait.pid;begin;Process.kill('INT',pid);rescue Errno::ESRCH;end}
    end
   end
  end
 end
 jobs.each(&:join)
ensure
 control.close;target.close;threads.each(&:join)
 termux_input&.close
 if termux_wait
   begin; Timeout.timeout(5){termux_wait.value};rescue Timeout::Error;Process.kill('TERM',termux_wait.pid);termux_wait.value;end
 end
 system(adb,'-s',device,'reverse','--remove',"tcp:#{port}")
end
exit(statuses.all?(&:zero?) ? 0 : 1)
