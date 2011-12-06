require 'cora'
require 'siri_objects'

#######
# This is a "hello world" style plugin. It simply intercepts the phrase "test siri proxy" and responds
# with a message about the proxy being up and running (along with a couple other core features). This 
# is good base code for other plugins.
# 
# Remember to add other plugins to the "config.yml" file if you create them!
######

class SiriProxy::Plugin::Hello < SiriProxy::Plugin

  listen_for /say hello/i do
    say "Hello.  Siri Proxy is up and running!" #say something to the user!
    request_completed #always complete your request! Otherwise the phone will "spin" at the user!
  end
  

end
