require 'cora'
require 'siri_objects'
require 'nokogiri'
require 'open-uri'

#######
# Queries Chapel Hill's next bus service
######

class SiriProxy::Plugin::NextBus < SiriProxy::Plugin


  #redundant: this is defined in my custom plungin manage siriproxypm-clientcachestae
  def get_app_config(*args)
    result = $APP_CONFIG
    if args != nil \
      && (first_arg = args.shift) != nil 
      eval "result = result.#{first_arg}"
      args.each do |arg|
        if arg == nil \
          || result  == nil \
          || !result.respond_to?('has_key?')\
          || !result.has_key?(arg)
          result = nil
          break
        end          
        result = result[arg]
      end
    end
    return result
  end

  #redundant:  this is defined in my custom plungin manage siriproxypm-clientcachestate
  def ensure_regexp(regexp) 
    if regexp != nil
      regexp.is_a?(String) 
      if regexp[0] == '/'
        #try to make it into a regexp
        regexp = eval regexp
      elsif  
        regexp = Regexp.new("^\s*#{regexp}",true);
      end
    end
    if regexp == nil || !regexp.is_a?(Regexp)
      regexp = nil
    end
    return regexp
  end

  def add_listeners(regexps,options = {},&block) 
    if regexps == nil 
      return
    end
    if !regexps.respond_to?('each') 
      #may be a scalar value
      regexps = [regexps]
    end
    regexps.each do |regexp|
      if (regexp = ensure_regexp(regexp)) == nil \
        || !regexp.is_a?(Regexp)
        next
      end
      listen_for(regexp,options,block)
    end
  end

  def initialize(config)
    location = get_app_config("next_bus","location")
    if location == nil  || !location.is_a?(String)
      return
    end
    buses = get_app_config("next_bus","routes")
    if buses != nil \
      && buses.respond_to?('each')
      buses.each do |bus_data|
        if bus_data == nil \
          || !bus_data.respond_to?('has_key?') 
          next
        end
        route = bus_data["route"]
        stop = bus_data["stop"]
        direction = bus_data["direction"]
        identify = bus_data["identify"]
        if route == nil || stop == nil || direction == nil || identify == nil 
          next
        end
        add_listeners(identify) {show_next_bus(route,direction,stop)}
      end
  end
  

  listen_for()  {show_next_bus('NS','S','airpwest_s')}

  def show_next_bus(route,direction,stop)
    say "Let me check" 
    when = get_next_bus(route,direction,stop)
    if when  == nil
      say "Sorry. I could not find the next bus"
    else
      say "The next #{route} bus is in #{when} minutes"
    end
    request_completed
  end

  def get_next_bus(route,director,stop) 
    #http://www.nextbus.com/predictor/fancyBookmarkablePredictionLayer.shtml?a=chapel-hill&r=NS&d=S&s=airpwest_s&ts=airprigg_s
    url = "http://www.nextbus.com/predictor/fancyBookmarkablePredictionLayer.shtml?a=chapel-hill&r=#{route}&d=#{direction}&s=#{stop}"
    log "Requesting #{url}"
    doc = Nokogiri::HTML(open(url))
    # doc.xpath('//h1/a[@class="blue"]').each do |link|
    #   puts link.content
    # end
    return "10"
  end
  
  

  



end
