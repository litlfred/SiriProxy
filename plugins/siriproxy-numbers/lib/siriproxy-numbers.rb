require 'cora'
require 'siri_objects'

#######
# This is a plugin illustating requesting a number from the user
######

class SiriProxy::Plugin::Numbers < SiriProxy::Plugin
  def initialize(config)
    #if you have custom configuration options, process them here!
  end
  
  #demonstrate capturing data from the user (e.x. "Siri proxy number 15")
  listen_for /my number is ([0-9,]*[0-9])/i do |number|
    say "Detected number: #{number}"
    
    request_completed #always complete your request! Otherwise the phone will "spin" at the user!
  end

end
