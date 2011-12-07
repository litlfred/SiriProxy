require 'cora'
require 'siriproxy/plugin_manager'
require 'socket' 
require 'siriproxypm-clientstatecache'

class SiriProxy::PluginManager::Honey < SiriProxy::PluginManager::ClientStateCache


  ###############################################
  #plugins
  ###############################################
  


  def get_plugin_list
    result = get_app_config("speakers",get_speaker,"plugins")
    if result == nil || !result.is_a?(Array) 
      result = []
    end
    return result
  end


  def process_plugins(text)
    result = nil
    speaker = get_speaker
    log "Incoming speaker #{speaker}"
    if  (result = switch_speaker(text ))== nil 
      log "Did not switch speaker.  will prcess #{text} on parent"
      result = super(text)
    end
    return result
  end

  ###############################################
  #access methods for client :speaker state
  ###############################################


  def set_speaker(new_speaker)
    set_client_state(:speaker,new_speaker)
  end

  def get_speaker
    speaker = nil
    if has_open_connection 
      speaker = get_client_state(:speaker)
    end
    if speaker == nil
      speaker = get_default_speaker
    end
    return speaker
  end

  ###############################################
  #handle switching/recognition of speaker
  ###############################################


  def get_default_speaker 
    default_speaker = nil
    client = get_client
    speakers = get_app_config('speakers')
    clients = get_app_config('client_preferences')
    if client != nil \
      && clients != nil \
      && clients.respond_to?('each') \
      && speakers.respond_to?('has_key?')
      clients.each do |range,client_preferences| 
        if !client_preferences \
          || !client_preferences.has_key?("speakers")  \
          || !in_range(client,range)  
          next
        end
        if client_preferences['speakers'].respond_to?("each") 
          speakers = client_preferences['speakers']
        else
          speakers = [client_preferences['speakers']]
        end
        if speakers != nil \
          && speakers.respond_to?('keys') \
          && (keys = speakers.keys) != nil \
          && keys.count > 0 
          return speakers[keys[0]]
        end
      end
    end
    return nil
  end

  #if switch speaker, return the name of the new speaker
  def switch_speaker(text) 
    new_speaker = nil
    speakers = get_app_config("speakers")
    if speakers != nil && speakers.respond_to?('each')   
      speakers.each do |speaker,speaker_config|
        if identify_speaker(speaker,text)
          new_speaker = speaker
          break
        end
      end
    end
    if new_speaker != nil && (client = get_client) != nil
      #verify on this ip address
      valid_speaker = false
      client_preferences = get_app_config("client_preferences")
      if client_preferences.respond_to?('each') 
        client_preferences.each do |range,client_preferences| 
          if client_preferences == nil\
            || !client_preferences.respond_to?("has_key?") \
            || !client_preferences.has_key?("speakers") \
            || client_preferences['speakers'] == nil  \
            || !in_range(client,range) 
            next
          end
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
        welcome_speaker(new_speaker)
      else
        log "someone tried to access #{new_speaker} from #{client} without permission"
        new_speaker = nil
      end
    end
    return new_speaker
  end



  def identify_speaker(speaker,text) 
    return text_matches(text,get_app_config("speakers",speaker,"identify"));
  end


  def welcome_speaker(speaker)    
    if (welcome = get_app_config("speakers",speaker,"welcome")) != nil
      respond(welcome)
    end
  end









end
