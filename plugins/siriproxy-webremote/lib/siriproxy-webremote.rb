require 'cora'
require 'siri_objects'

#######
#Saying "honey XXX YYY ZZZ" will generate the GET request http://honey/webRemote?remote=XXXX&code[0]=YYY&code[1]=ZZZZ.}
######

class SiriProxy::Plugin::WebRemote < SiriProxy::Plugin
  def initialize(config)
    #if you have custom configuration options, process them here!
  end


  
  #demonstrate capturing data from the user (e.x. "Siri proxy number 15")
  listen_for /vanilla (\s+) (\s+)/i do |m|
    say "web remote honey: {#m.inspect}"
    
    request_completed #always complete your request! Otherwise the phone will "spin" at the user!
  end


  #demonstrate capturing data from the user (e.x. "Siri proxy number 15")
  listen_for /honey (\s+) ((\s+) )+/i do |m|
    say "web remote honey: {#m.inspect}"
    
    request_completed #always complete your request! Otherwise the phone will "spin" at the user!
  end




end
