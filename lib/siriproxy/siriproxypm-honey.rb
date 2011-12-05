require 'plugin_manager'

class SiriProxy::PluginManager::Honey < SiriProxy::PluginManager::ClientCaching
  
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

  def intialize() 
    super(initialize) #calls load_plugins
    init_speaker_stack
  end

  def init_speaker_stack
    if @@speaker_stack == nil 
      @@speaker_stack = {}
      @speakers.each speaker do
        @@speaker_stack[speaker] = {}  #hash is client (e.g. ip address) value is nil if non-default spear
      end
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
  
  def  do_call_back
    log "Active callback found, resuming"

    # We must set the active callback to nil first, otherwise
    # multiple callbacks within one listen block won't work
    callback = @callback
    @callback = nil
    callback.call(text)
    return true
  end

  

  def get_default_speaker() 
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

  def get_client 
    port, ip = Socket.unpack_sockaddr_in(@iphone_conn.get_peername)
    return ip;
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
      welcome_speaker(speaker)
    end
    return new_speaker
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


  def process(text)
    result = nil
    log "Processing '#{text}'"
    do_call_back if @callback

    if ! identified(text)
      return 
    end

    if result = switch_speaker(text) or result = process_speaker_plugins(text)
      self.guzzoni_conn.block_rest_of_session 
    else
      log "No matches for '#{text}'"
      no_matches
    end
    return result
  end


  def set_speaker(new_speaker)
    client = get_client()
    if client == nil
      return
    end
    #client never accessed before, get the default speaker for this client
    if  @@speaker_stack[client] == nil
      if default_speaker = get_default_speaker(client)
        @@speaker_stack[client] = [default_speaker]
      end
    end
    #if the new speaker is already in the clients speaker stack, 
    #drop everything above it in the stack.
    #otherwise add the new speaker onto the end of the stack
    found = @@speaker_stack[client].index new_speaker
    if found != nil      
      @@speaker_stack[client].slice!(0,found +1)
    else
      @@speaker_stack[client].push(new_speaker)
    end
  end

  def process_speaker_plugins(text)
    client = get_client
    if client == nil
      return
    end
    result = nil
    if !@@speaker_stack[client].kind_of? Array || @@speaker_stack[client].count = 0
      return nil
    end


    #really go through the speaker stack starting at the end. until we find one that has not expired
    #then process plugins for that speaker.
    
    speaker = @@speaker_stack[client][-1]

    @speaker_plugins[speaker].each do |plugin|     
      if plugin = @plungins[plugin] && result = plugin.process(text)      
        break
      end
    end
    return result
  end


  def set_speaker_priority_plugin(speaker,plugin)
    if !@speaker_plugins[speaker] || !@speaker_plugins[speaker].kind_of?(Array)
      return
    end
    @speaker_plugins[speaker].delete(plugin)
    @speaker_plugins[speaker].unshift(plugin)
  end

end
