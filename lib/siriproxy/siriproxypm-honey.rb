require 'plugin_manager'

class SiriProxy::PluginManager::Honey < SiriProxy::PluginManager

  #intialization

  def intialize() 
    super(initialize) #calls load_plugins
    init_speaker_stack
  end
  
  def init_speaker_stack
    if @@speaker_stack == nil       
      #create hash of arrays.  key is client (e.g. ipaddress) 
      @@speaker_expires = {}
      @@speaker_stack = {}
    end
  end

  def load_plugins
    @speakers = []
    @speaker_plugins = {}
    if $APP_CONFIG.speakers
      $APP_CONFIG.speakers.each do |speaker_config|
        if  !speaker_config.name || ! speaker_config.name.is_a?(String)
          next
        end
        @speakers << speaker_config.name
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
    @honey = "honey"
    if  $APP_Config.PluginManager.name && $APP_Config.PluginManager.name.is_a?(String)
      @honey = APP_Config.PluginManager.name
    end

    matchdata = text.match /^#{@honey}\s/i
    if  ! matchdata.string 
      return nil
    end
    return matchdata.post_match
  end


  #if switch speaker, return the name of the new speaker
  def switch_speaker(text) 
    new_speaker = nil
    @@speakers.each do |speaker|
      if is_identified(speaker,text)
        new_speaker = speaker
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
    if client = get_client  && @@speaker_stack[client].respond_to?(each)
      #really go through the speaker stack starting at the end. until we find one that has not expired
      #then process plugins for that speaker.
      speaker  = nil
      while !speaker &&  @@speaker_stack[client].count > 0
        t_speaker = @@speaker_stack[client]
        if speaker_expired(client,t_speaker)
          @@speaker_stack[client].pop()      
        else
          speaker = t_speaker
          break
        end
      end      
    end
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
    if  !@@speaker_stack[client] 
      #client never accessed before, or all valid speakers have been pushed off.. get the default speaker for this client
      if default_speaker = get_default_speaker(client)
        @@speaker_stack[client] = [default_speaker]
      else
        @@speaker_stack[client] = []
      end
    end
    #if the new speaker is already in the clients speaker stack, 
    #drop everything above it in the stack.
    #otherwise add the new speaker onto the end of the stack
    if (found = @@speaker_stack[client].index(new_speaker)) != nil
      @@speaker_stack[client].slice!(0,found +1)
    else
      @@speaker_stack[client].push(new_speaker)
    end
  end


  def get_default_speaker 
    default_speaker = nil
    if @speakers.count > 0
        default_speaker = @speakers[0]
    end
    client = get_client()
    if client != nil \
      && $APP_CONFIG.client_preferences  \
      &&  client_preferences = $APP_CONFIG.client_preferences.const_get(client)  \
      && client_preferences.speaker.is_a?(String) \
      && @speakers.include?(client_preferences.speaker)
      default_speaker = client_preferences.speaker
    end
    return default_speaker
  end


  def set_priority_plugin(plugin)
    if ! speaker = get_speaker || !@speaker_plugins[speaker] || !@speaker_plugins[speaker].kind_of?(Array)
      return
    end
    @speaker_plugins[speaker].delete(plugin)
    @speaker_plugins[speaker].unshift(plugin)
  end


  #speaker activity expiration
  def is_expired(speaker)
    result = true
    #@@speakers_expires[client][speaker] -- value of 0/false/nil is always expired.  value of > 0 is time of expiration, value of <0 means never expire
    if client = get_client  && @@speaker_expires[client] &&  expire_time  =@@speakers_expires[client][speaker]
      if expire_time < 0
        result  = false
      else 
        result = Time.now.to_i > expire_time
      end
    end
    return result
  end

  def set_expiration(speaker,expiration) 
    if client = get_client
       @@speaker_expires[client][speaker] = expiration
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




end
