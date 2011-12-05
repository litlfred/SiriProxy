require 'eventmachine'
require 'zlib'
require 'pp'

class String
  def to_hex(seperator=" ")
    bytes.to_a.map{|i| i.to_s(16).rjust(2, '0')}.join(seperator)
  end
end

class SiriProxy
  
  def initialize()
    # @todo shouldnt need this, make centralize logging instead
    $LOG_LEVEL = $APP_CONFIG.log_level.to_i

    pm = nil    
    
    if $APP_CONFIG.PluginManager && $APP_CONFIG.PluginManager.class && $APP_CONFIG.PluginManager.class is_a?  String 
      class=$APP_CONFIG.PluginManager.class
      requireName = "siriproxypm-#{class.downcase}"
      klass = SiriProxy.const_get(class)
      if not klass.is_a?(Class)
        raise "Specified plugin manager #{class} is not a class"
      end
      pm = SiriProxy::PluginManager.const_get(class).new
      if !pm.ancestors.include? SiriProxy::PluginManager
        raise "Cannot create plugin manager #{APP_CONFIG.PluginManager}"
      end
    else
      pm = SiriProxy::PluginManager.new
    end
    
    EventMachine.run do
      begin
        puts "Starting SiriProxy on port #{$APP_CONFIG.port}.."
        EventMachine::start_server('0.0.0.0', $APP_CONFIG.port, SiriProxy::Connection::Iphone) { |conn|
          $stderr.puts "start conn #{conn.inspect}"
          conn.plugin_manager = pm
          conn.plugin_manager.iphone_conn = conn
        }
      rescue RuntimeError => err
        if err.message == "no acceptor"
          raise "Cannot start the server on port #{$APP_CONFIG.port} - are you root, or have another process on this port already?"
        else
          raise
        end
      end
    end
  end
end
