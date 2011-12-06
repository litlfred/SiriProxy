require 'cora'
require 'siriproxy/plugin_manager'
require 'socket' 

class SiriProxy::PluginManager::Honey < SiriProxy::PluginManager

  #intialization
  def initialize()
    super() #calls load_plugins
    init_client    
  end
  
  @@client_state = nil

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
    if $APP_CONFIG.speakers != nil && $APP_CONFIG.speakers.respond_to?('each') 
      $APP_CONFIG.speakers.each do |name,speaker_config|
        plugins = []
        if speaker_config['plugins'] != nil && speaker_config['plugins'].respond_to?('each')
          plugins = speaker_config['plugins']
        end
        @speaker_plugins[name] = {}
        plugins.each do |plugin|
          if (plugin_obj = instantiate_plugin(plugin)) == nil
            next
          end
          @speaker_plugins[name][plugin]  = plugin_obj
        end
      end
    end 
  end


  def instantiate_plugin(plugin) 
    plugin_obj = nil
    if $APP_CONFIG.plugins != nil && $APP_CONFIG.plugins.respond_to?('each')
      $APP_CONFIG.plugins.each do |pluginConfig|
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
            break
          end
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
    if  (proc_text = requested(text)) == nil
      no_matches
      return nil
    end
    log "Got Honey Command: #{proc_text}"
    if result = switch_speaker(proc_text ) ||  result = process_plugins(proc_text)
      self.guzzoni_conn.block_rest_of_session 
    else
      log "No matches for '#{proc_text}' on honey"
      prompt_speaker
    end
    send_request_complete_to_iphone
    return result
  end

  def prompt_speaker
    speaker = get_speaker
    if (speaker) 
      respond( "Hello #{speaker}.  What do you want?",{})
    end
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
  def requested(text)
    result = nil
    identifiers = ["honey"]
    if  $APP_CONFIG.pluginManager.has_key?('identifier') \
      && $APP_CONFIG.pluginManager['identifier'] != nil 
      if  $APP_CONFIG.pluginManager['identifier'].is_a?(String)
        identifiers = [$APP_CONFIG.pluginManager['identifier']]
      else
        identifiers = $APP_CONFIG.pluginManager['identifier']
      end
    end
    identifiers.each do |identifier|
      if identifier[0] == '/'
        regexp = eval identifier
      else 
        regexp = Regexp.new("^\s*#{identifier}\s",true);
      end
      if ( regexp && regexp.is_a?(Regexp) && matchdata = text.match(regexp))
        result =  matchdata.post_match
        break
      end
    end
    return result
  end


  #if switch speaker, return the name of the new speaker
  def switch_speaker(text) 
    new_speaker = nil
    if $APP_CONFIG.speakers && $APP_CONFIG.speakers.respond_to?('each')   
      $APP_CONFIG.speakers.each do |speaker,speaker_config|
        if is_identified(speaker,text)
          new_speaker = speaker
          break
        end
      end
    end
    if new_speaker != nil && (client = get_client) != nil
      #see what our client ip address is
      valid_speaker = false
      if $APP_CONFIG.client_preferences \
        && $APP_CONFIG.client_preferences.respond_to?('each') 
        $APP_CONFIG.client_preferences.each do |range,client_preferences| 
          if !in_range(client,range) \
            || client_preferences == nil\
            || !client_preferences.respond_to?("has_key?") \
            || !client_preferences.has_key?("speakers") \
            || client_preferences['speakers'] == nil 
            next
          end
          log client_preferences['speakers']
          if (client_preferences['speakers'].is_a?(String) && client_preferences['speakers'] == new_speaker) \
            ||( client_preferences['speakers'].respond_to?("include?") && client_preferences['speakers'].include?(new_speaker))
            valid_speaker = true
            break
          end
        end
      end
      if valid_speaker
        log "Switching to #{new_speaker} on #{client}"
        set_speaker(new_speaker)
        register_activity(new_speaker)
        welcome_speaker(new_speaker)
      else
        log "someone tried to access #{new_speaker} from #{client} without permission"
        new_speaker = nil
      end
    end
    return new_speaker
  end


  def process_plugins(text)
    result = nil
    if (speaker = get_speaker) != nil && @speaker_plugins.has_key?(speaker)
      log "Processing text for speaker #{speaker}"
      @speaker_plugins[speaker].each do |plugin,plugin_obj|     
        if result = plugin_obj.process(text)      
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
    if (client = get_client) != nil  \
      && @@client_state.has_key?(client) \
      && @@client_state[client]["speakers"].respond_to?('each')
      #go through the speaker stack starting at the end. until we find one that has not expired
      speaker  = nil
      while !speaker  &&  @@client_state[client]["speakers"].count > 0
        t_speaker = @@client_state[client]["speakers"][-1]
        if speaker_expired(t_speaker)
          log "Speaker #{t_speaker} expired"
          @@client_state[client]["speakers"].pop()      
        else
          speaker = t_speaker
          break
        end
      end      
    end
    #if everyone is expired. we could have exhaushed all of our speakers for our client.  
    #however the call to get_default_speaker will repopulate speakers lsit with the default speaker
    if speaker == nil
      speaker = get_default_speaker
    end
    return speaker
  end

 

  def get_client 
    port, ip = Socket.unpack_sockaddr_in(@iphone_conn.get_peername)
    return ip;
  end





  def is_identified(speaker,text) 
    if $APP_CONFIG.speakers == nil \
      || !$APP_CONFIG.speakers.has_key?(speaker) \
      || ( speaker_config = $APP_CONFIG.speakers[speaker]) == nil \
      || speaker_config['identify'] == nil
      return false
    end
    if !speaker_config['identify'].kind_of? Array
      list = [ speaker_config['identify'] ]
    else
      list = speaker_config['identify']
    end
    list.each do |identifier|
      if !identifier.is_a?(String) 
        next
      end
      if identifier[0] == '/'
        #try to make it into a regexp
        regexp = eval identifier
      elsif  
        regexp = Regexp.new("^\s*#{identifier}\s",true);
      end
      if  regexp && regexp.is_a?(Regexp) && text.match(regexp)
        return true
      end
    end
    return false
  end


  def welcome_speaker(speaker)    
    if !$APP_CONFIG.speakers == nil \
      || !$APP_CONFIG.speakers.respond_to?('has_key?') \
      || !$APP_CONFIG.speakers.has_key?(speaker) \
      || (speaker_config = $APP_CONFIG.speakers[speaker]) == nil \
      || ! speaker_config.respond_to?('has_key?') \
      || ! speaker_config.has_key?('welcome') \
      || ! speaker_config['welcome']
      return
    end
    respond(speaker_config['welcome'])
  end



  def set_speaker(new_speaker)
    client = get_client()
    if client == nil
      return
    end
    if  !@@client_state[client] 
      #client never accessed before, or all valid speakers have been pushed off.. get the default speaker for this client
      if default_speaker = get_default_speaker
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

  

  def get_default_speaker 
    default_speaker = nil
    if (client = get_client()) != nil    \
      && $APP_CONFIG.client_preferences != nil \
      && $APP_CONFIG.client_preferences.respond_to?('each') \
      && $APP_CONFIG.speakers != nil \
      && $APP_CONFIG.speakers.respond_to?('has_key?') 
      $APP_CONFIG.client_preferences.each do |range,client_preferences| 
        if !in_range(client,range)  \
          || !client_preferences \
          || !client_preferences.has_key?("speakers") 
          next
        end
        if client_preferences['speakers'].respond_to?("each") 
          speakers = client_preferences['speakers']
        else
          speakers = [client_preferences['speakers']]
        end
        speakers.each do |speaker|       
          if speaker == nil || !speaker.is_a?(String)
            next
          end
          if  $APP_CONFIG.speakers.has_key?(speaker)
            default_speaker = speaker
            break
          end
        end
      end
    end
    return default_speaker
  end




  #speaker activity expiration
  def speaker_expired(speaker)
    result = true
    #  expire time -- value of 0/false/nil is always expired.  value of > 0 is time of expiration, value of <0 means never expire
    if (client = get_client)!=nil  \
      && @@client_state.has_key?(client) \
      && @@client_state[client] != nil \
      && (expire_time = @@client_state[client]["expires"][speaker]) != nil
      if expire_time < 0
        result  = false
      else 
        result = Time.now.to_i > expire_time
      end      
    end
    return result
  end

  def set_expiration(speaker,expiration) 
    if (client = get_client )!=nil \
      && @@client_state[client] != nil
       @@client_state[client]["expires"][speaker] = expiration
    end
  end

  def register_activity(speaker)
    expires = 600
    log "registering activity for #{speaker}"
    if $APP_CONFIG.speakers != nil \
      && $APP_CONFIG.speakers.has_key?(speaker) \
      && (speaker_config = $APP_CONFIG.speakers[speaker]) != nil \
      && speaker_config.respond_to?('has_key?') \
      && speaker_config.has_key?('expires') \
      && speaker_config['expires'] != nil
      expires = speaker_config['expires']
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
    @speaker_plugins[speaker] = plugins
  end

end
