require 'cora'
require 'siriproxy/plugin_manager'
require 'socket' 

class SiriProxy::PluginManager::ClientStateCache < SiriProxy::PluginManager



  ###############################################
  #initialization
  ###############################################

  # @@client_state = nil

  #intialization
  def initialize()
    super() #calls load_plugins
    init_client    
  end



  def get_client 
    port, ip = Socket.unpack_sockaddr_in(@iphone_conn.get_peername)
    return ip;
  end
  


  def init_client
    #create hash of array of stack states:  key is client (e.g. ipaddress)  value is hash with
    #only used key is :activity, which gives the last time activity was registered from this client
    @client_state = {}
  end
  
  def set_client_state(symbol,val) 
    client = get_client()
    if client != nil 
      if !@client_state.has_key?(client) \
        || @client_state[client] == nil
        @client_state[client] = {}
      end
      @client_state[client][symbol]  = val
    end
  end

  def get_client_state(symbol) 
    result = nil
    client = get_client()
    if client != nil && @client_state.has_key?(client)
      result = @client_state[client][symbol]
    end
    return result
  end

  ###############################################
  #loading of plugins
  ###############################################
  
  

  def get_plugin_list
    result = []
    if (plugin_configs = get_app_config("plugins") ) != nil \
      && plugin_configs.respond_to?('each')
      plugin_configs.each do |plugin_config|
        if plugin_config == nil \
          || !plugin_config.respond_to?('has_key?')  \
          || !plugin_config.has_key?('name') \
          || plugin_config["name"] == nil
          next
        end
        result << plugin_config["name"]
      end
    end
    return result
  end


  def process_plugins(text)
    result = nil
    plugins = get_plugin_list
    plugins.each do |plugin|
      plugin_obj = instantiate_plugin(plugin)
      if plugin_obj == nil || !plugin_obj.is_a?(SiriProxy::Plugin)
        next
      end
      if result = plugin_obj.process(text)      
        break
      end
    end
    return result
  end

  def instantiate_plugin(plugin) 
    plugins = get_app_config("plugins")
    if plugins != nil && plugins.respond_to?('each')
      plugins.each do |pluginConfig|
        if pluginConfig.is_a? String
          class_name = pluginConfig
          name = pluginConfig
          require_name = "siriproxy-#{class_name.downcase}"
        elsif   pluginConfig['name'] != nil && pluginConfig['name'].is_a?(String)
          name =pluginConfig['name']
          class_name = pluginConfig['name']
          require_name = pluginConfig['require'] || "siriproxy-#{class_name.downcase}"
        end

        if name == plugin && require_name.length > 0  && class_name.length > 0 
          require require_name
          if (klass = SiriProxy::Plugin.const_get(class_name)).is_a?(Class)
            plugin_obj = klass.new(pluginConfig)
            plugin_obj.manager = self
            return plugin_obj
            break
          end
        end
      end
    end
    return nil
  end


  ###############################################
  #regexp and ip range helper functions
  ###############################################
    
  #@todo.  make sure it  matches the range specifications in dnsmasq
  def in_range(client,range) 
    range.split(",").each do |ranges|
      pieces = ranges.split("-")
      if pieces.count == 1 && pieces[0] == client
        return true
      elsif pieces.count == 2
        addr = client.split(".")[3]
        ip_beg = pieces[0].split(".")[3]
        ip_end = pieces[1].split(".")[3]
        if ip_beg != nil \
          && ip_end != nil \
          && addr != nil \
          && ip_beg <= addr \
          && addr <= ip_end 
          return true
        end
      end
    end
    return false
  end

    
  def text_matches(text,list, default_list = [],post =false)    
    text = text.strip
    if post
      result =  nil
    else
      result = false
    end
    if text == nil
      return result
    end
    if list == nil 
      list = default_list
    elsif list.is_a?(String)
      list = [list]
    elsif !list.respond_to?('each')
      list = default_list
    end
    list.each do |regexp|
      if regexp == nil
        next
      end
      if regexp.is_a?(String) 
        if regexp[0] == '/'
          #try to make it into a regexp
          regexp = eval regexp
        elsif  
          regexp = Regexp.new("^\s*#{regexp}",true);
        end
      end
      if regexp == nil || !regexp.is_a?(Regexp)
        next
      end
      if post
        if   (match_data = regexp.match(text)) != nil
          result =  match_data.post_match
          break
        end
      else
        if  text.match(regexp)
          result =  true
          break
        end
      end
    end
    return result
  end



  ###############################################
  #convienence methods for client :activity state
  ###############################################
  def close_connection
    set_client_state(:activity,0)
  end

  def keep_open_connection
    set_client_state(:activity,Time.now.to_i)
  end


  def has_open_connection
    open = get_app_config("pluginManager","open")
    activity = get_client_state(:activity)  
    result =  open != nil && activity != nil && open.is_a?(Integer) && activity.is_a?(Integer) && (activity + open >= Time.now.to_i )
  end
  

  ###############################################
  #convience methods for access application config
  ###############################################

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




  ###############################################
  #main text processing
  ###############################################

  def process(text)
    result = nil
    log "Processing '#{text}'"
    do_call_backs
    proc_text = requested(text)
    log "Processing proc '#{text}'"
    if  has_open_connection 
      log "Connection is still open"
      if proc_text == nil
        #there was not request to honey made, so we need to process the original text
        proc_text = text        
      end
    elsif proc_text == nil
      log "No open connection -- passing back to siri"
      no_matches
      return nil
    end
    log "Got Honey Command: #{proc_text}"
    keep_open_connection
    if proc_text \
      && (result = is_goodbye(proc_text) \
          || result = process_plugins(proc_text))
      self.guzzoni_conn.block_rest_of_session 
    else
      log "No matches for '#{proc_text}' on honey"
      prompt
    end
    send_request_complete_to_iphone
    return result
  end

  def prompt
    respond( "Hello.  What did you want?",{})
  end
  
  def  do_call_backs
    if !@callback
      return
    end
    log "Active callback found, resuming"
    # We must set the active callback to nil first, otherwise
    # multiple callbacks within one listen block won't work
    callback = @callback
    @callback = nil
    callback.call(text)
    return true
  end



  def is_goodbye(text) 
    result = false
    goodbyes = get_app_config("pluginManager","goodbye")
    if (result = text_matches(text,goodbyes))      
      log "Saying goodbye"
      close_connection
      result = true
    end
    return result
  end

  


  #returns nil if we need to ignore this text.  otherwise it returns the 
  #remainder of the text to be processed
  def requested(text)
    return text_matches(text,get_app_config("pluginManager","identifier"),['honey'],true)
  end





end
