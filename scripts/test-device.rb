$stdout.sync=true
require 'open3'
adb=ENV.fetch('ADB', 'adb')
device=ARGV.fetch(0) { abort 'Usage: ruby scripts/test-device.rb <adb-device-id>' }
background=nil
status=nil
Open3.popen2e('flutter','test','integration_test/tunnel_test.dart','-d',device,'--reporter','expanded') do |stdin,out,wait|
 stdin.close
 out.each_line do |line|
  puts line
  if line.include?('TAILTAP_BACKGROUND_WINDOW') && background.nil?
   background=Thread.new do
    system(adb,'-s',device,'shell','am','start','-a','android.intent.action.MAIN','-c','android.intent.category.HOME',out:File::NULL)
    sleep 3
    state,_=Open3.capture2(adb,'-s',device,'shell','dumpsys','activity','services','dev.tailtap.tail_tap')
    puts(state.include?('isForeground=true') ? 'HOST: foreground service remains active in background' : 'HOST: foreground service flag missing')
    sleep 5
    system(adb,'-s',device,'shell','am','start','-n','dev.tailtap.tail_tap/.MainActivity',out:File::NULL)
   end
  end
 end
 status=wait.value
end
background&.join
exit status.exitstatus
