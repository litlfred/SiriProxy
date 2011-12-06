require 'plugin_manager'

class SiriProxy::PluginManager::Honey < SiriProxy::PluginManager

  #intialization

  def intialize() 
    super(initialize) #calls load_plugins
    init_client
  end
  
  def init_client
    if @@client_state == nil       
      #create hash of array of stack states:  key is client (e.g. ipaddress)  value is hash with
      #key "speakers"  is an array of speaker names 
      #key "expires" is a hash with keys speaker and values an expire time (unix timestamp)
      #containing state data under "speakers" and expiration time under "expires"
      @@client_state = {}
    end
    
  end

  def load_plugins
    @speaker_plugins = {}
    if $APP_CONFIG.speakers && $APP_CONFIG.speakers.respond_to?(each) 
      $APP_CONFIG.speakers.each do |speaker_config|
        if  !speaker_config.name || ! speaker_config.name.is_a?(String)
          next
        end
        plugins = []
        if speaker_config.plugins && speaker_config.plugins.respond_to?(each)
          plugins = speaker_config.plugins
        end
        @speaker_plugins[speaker_config.name] = {}
        plugins.each do |plugin|
          @speaker_plugins[speaker_config.name][plugin] = instantiate_plugin(plugin)
        end
      end
    end 
  end


  def instantiate_plugin(plugin) 
    plugin_obj = nil
    if $APP_CONFIG.plugins
      $APP_CONFIG.plugins.each do |pluginConfig|
        if pluginConfig.is_a? String
          className = pluginConfig
          name = pluginConfig
          requireName = "siriproxy-#{className.downcase}"
        elsif   pluginConfig.name && pluginConfig.name.is_a?(String)
          name =pluginConfig['name']
          className = pluginConfig['name']
          requireName = pluginConfig['require'] || "siriproxy-#{className.downcase}"
        end
        if name == plugin && requireName
          require requireName
          plugin_obj = SiriProxy::Plugin.const_get(className).new(pluginConfig)
          plugin_obj.manager = self
          break
        end
      end
    end
    return plugin_obj
  end


  #main text processing

  def process(text)
    result = nil
    log "Processing '#{text}'"
    do_call_backs

    if ! identified(text)
      return 
    end

    if result = switch_speaker(text) || result = process_plugins(text)
      self.guzzoni_conn.block_rest_of_session 
    else
      log "No matches for '#{text}'"
      no_matches
    end
    return result
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


  #returns nil if we need to ignore this text.  otherwise it returns the 
  #remainder of the text to be processed
  def identified(text)
    honey = "honey"
    if  $APP_Config.PluginManager.name && $APP_Config.PluginManager.name.is_a?(String)
      honey = APP_Config.PluginManager.name
    end

    matchdata = text.match /^#{honey}\s/i
    if  ! matchdata.string 
      return nil
    end
    return matchdata.post_match
  end


  #if switch speaker, return the name of the new speaker
  def switch_speaker(text) 
    new_speaker = nil
    if $APP_CONFIG.speakers && $APP_CONFIG.speakers.respond_to?(each)   
      $APP_CONFIG.speakers.each do |speaker,speaker_config|
        if is_identified(speaker,text)
          new_speaker = speaker
          break
        end
      end
    end
    if new_speaker
      set_speaker(new_speaker)
      register_activity(speaker)
      welcome_speaker(speaker)
    end
    return new_speaker
  end


  def process_plugins(text)
    result = nil
    if speaker = get_speaker && @speaker_plugins[speaker]
      @speaker_plugins[speaker].each do |plugin|     
        if plugin_obj = @plugins[plugin] && result = plugin_obj.process(text)      
          register_activity(speaker)
          break
        end
      end
    end
    return result
  end



  #handling of speakers

  
  def get_speaker
    speaker = nil
    if client = get_client  \
      && @@client_state[client] \
      && @@client_state[client]["speakers"].respond_to?(each)
      #go through the speaker stack starting at the end. until we find one that has not expired
      speaker  = nil
      while !speaker  &&  @@client_state[client]["speakers"].count > 0
        t_speaker = @@client_state[client]["speakers"][-1]
        if speaker_expired(client,t_speaker)
          @@client_state[client]["speakers"].pop()      
        else
          speaker = t_speaker
          break
        end
      end      
    end
    #if everyone is expired. we could have exhaushed all of our speakers for our client.  
    #however the call to get_default_speaker will repopulate speakers lsit with the default speaker
    if !speaker
      speaker = get_default_speaker
    end
    return speaker
  end

 

  def get_client 
    port, ip = Socket.unpack_sockaddr_in(@iphone_conn.get_peername)
    return ip;
  end




  #if identified, return the remainder of the text
  #otherwise return nil
  def is_identified(speaker,text) 
    if !$APP_CONFIG.speakers \
      || ! speaker_config = $APP_CONFIG.speakers.const_get(speaker) \
      || !speaker_config.identify
      return false
    end
    if !speaker_config.identify.kind_of? Array
      list = [ speaker_config.identify ]
    else
      list = speaker_config.identify
    end
    list.each do |identifier|
      if (identifier.is_a?(String) && idetifier == text) \
        || ( identifier.is_a?(RegExp) && text.match(identifier))
        return true
      end
    end
    return true
  end


  def welcome_speaker(speaker)    
    if !$APP_CONFIG.speakers \
      || ! speaker_config = $APP_CONFIG.speakers.const_get(speaker) \
      || ! speaker_config.welcome
      return
    end
    respond(speaker_config.welcome)
  end



  def set_speaker(new_speaker)
    client = get_client()
    if client == nil
      return
    end
    if  !@@client_state[client] 
      #client never accessed before, or all valid speakers have been pushed off.. get the default speaker for this client
      if default_speaker = get_default_speaker(client)
        speakers = [default_speaker]
      else
        speakers = []
      end
      @@client_state[client] = {"speakers"=>speakers,"expires" => {}}
    end
    #if the new speaker is already in the clients speaker stack, 
    #drop everything above it in the stack.
    #otherwise add the new speaker onto the end of the stack
    if (found = @@client_state[client]["speakers"].index(new_speaker)) != nil
      @@client_state[client]["speakers"].slice!(0,found +1)
    else
      @@client_state[client]["speakers"].push(new_speaker)
    end
  end

  def in_range(client,range) 
    client.split(",").each do |ranges|
      pieces = ranges.split("-")
      if pieces.count == 1 && pices[0] == client
        return true
      elsif pieces.count == 2
        ip_beg = pieces[0].split(".")[3]
        ip_end = pieces[1].split(".")[3]
        if ip_beg != nil \
          && ip_end != nil \
          && ip_beg <= client \
          && client <= ip_end 
          return true
        end
      end
    end
    return false
  end

  def get_default_speaker 
    default_speaker = nil
    if (client = get_client()) != nil    \
      && $APP_CONFIG.client_preferences \
      && $APP_CONFIG.client_preferences.respond_to?(each) \
      && $APP_CONFIG.speakers \
      && $APP_CONFIG.speakers.respond_to?(has_key) 
      $APP_CONFIG.client_preferences.each do |range,client_preferences| 
        if !in_range(client,range) 
          ||  !client_preferences \
          || !client_preferences.speaker
          next
        end
        
        if client_preferences.speaker.is_a?(String) 
          speakers = [client_preferences.speaker]
        else
          speakers = client_preferences.speaker
        end
        speakers.each do |speaker|       
          if  $APP_CONFIG.speakers.has_key(speaker)
            default_speaker = client_preferences.speaker        
            break
          end
        end
      end
    end
    return default_speaker
  end




  #speaker activity expiration
  def is_expired(speaker)
    result = true
    #  expire time -- value of 0/false/nil is always expired.  value of > 0 is time of expiration, value of <0 means never expire
    if client = get_client  \
      && @@client_state[client]\
      && expire_time = @@client_state[client]["expires"][speaker]
      if expire_time < 0
        result  = false
      else 
        result = Time.now.to_i > expire_time
      end
    end
    return result
  end

  def set_expiration(speaker,expiration) 
    if client = get_client \
      && @@client_state[client]
       @@client_state[client]["expires"][speaker] = expiration
    end
  end

  def register_activity(speaker)
    expires = 600
    if $APP_CONFIG.speakers \
      && speaker_config = $APP_CONFIG.speakers.const_get(speaker) \
      && speaker_config.expires != nil
      expires = speaker_config.expires
    end
    if expires > 0
      set_expiration(speaker, Time.now.to_i + expires)      
    elsif epxires < 0
      set_expiration(speaker, expires)
    else
      set_expiration(speaker,0)  #speaker is already expired
    end
      
  end


  #overide some methods in PluginManager and Cora to make them speaker aware.  don't know if these are used anywhere or not.

  def set_priority_plugin(plugin)
    if ! speaker = get_speaker || !@speaker_plugins[speaker] || !@speaker_plugins[speaker].kind_of?(Array)
      return
    end
    @speaker_plugins[speaker].delete(plugin)
    @speaker_plugins[speaker].unshift(plugin)
  end


  def get_plugins
    if ! speaker = get_speaker || !@speaker_plugins[speaker] || !@speaker_plugins[speaker].kind_of?(Array)
      return
    end
    return @speaker_plugins[speaker]
  end 

  def set_plugins(plugins)    
    if !plugins || !plugins.kind_of?(Array) || ! speaker = get_speaker 
      return
    end
    !@speaker_plugins[speaker] = plugins
  end

end
