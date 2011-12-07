require 'cora'
require 'siriproxy/plugin_manager'
require 'socket' 

class SiriProxy::PluginManager::ClientStateCache < SiriProxy::PluginManager



  ###############################################
  #initialization
  ###############################################

  @@client_state = nil

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
    if @@client_state == nil       
      #create hash of array of stack states:  key is client (e.g. ipaddress)  value is hash with
      #key :activity the last time activity was registered from this client
      @@client_state = {}
    end
  end
  
  def set_client_state(symbol,val) 
    client = get_client()
    if client != nil
      @@client[client][symbol]  = val
    end
  end

  def get_client_state(symbol) 
    result = nil
    client = get_client()
    if client != nil
      result = @@client[client][symbol]
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
      plugin_obj = instatiate_plugin(plugin)
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
    if list == nil 
      list = default_list
    elsif list.is_a?(String)
      list = [list]
    elsif !list.responds_to?('each')
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
          regexp = Regexp.new("^\s*#{regexp}\s",true);
        end
      end
      if regexp == nil || !regexp.is_a?(Regexp)
        next
      end
      if post
        if   (match_data = regexp.match(text)) != nil
          return match_data.post_match
        end
      else
        if  text.match(regexp)
          return true
        end
      end
    end
    return false
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
    return  ((open = get_app_config("open")) != nil) \
    && open.is_a?(Integer) \
    && activity = get_client_state(:activity)  \
    && activity + open >= Time.now.to_i 
  end
  

  ###############################################
  #convience methods for access application config
  ###############################################

  def get_app_config(*args)
    result = $APP_CONFIG
    if args != nil \
      && (first_arg = args.unshift) != nil
      result = result.const_get(first_arg)
      args.each do |arg|
        if arg == nil \
          ||config_data == nil \
          || !config_data.respond_to?('has_key?')\
          || !config_data.has_key?(arg)
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
    if  has_open_connection 
      log "Connection is still open"
      if  (proc_text = requested(text)) == nil
        #we may not need this block... if the text is stream in tokenized chunks to process
        proc_text = text
      end
    else
      if  (proc_text = requested(text)) == nil
        no_matches
        return nil
      end
    end
    log "Got Honey Command: #{proc_text}"
    keep_open_connection
    if result = is_goodbye(proc_text) \
      || result = process_plugins(proc_text)
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
      close_connection
    end
    return result
  end

  


  #returns nil if we need to ignore this text.  otherwise it returns the 
  #remainder of the text to be processed
  def requested(text)
    return text_matches(get_app_config("pluginManager","identifier"),['honey'],true)
  end





end
