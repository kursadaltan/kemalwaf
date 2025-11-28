require "./connection_pool"
require "./config_loader"
require "uri"
require "openssl"

module KemalWAF
  # Constants
  DEFAULT_CLEANUP_INTERVAL_MINUTES  =  5
  DEFAULT_IDLE_POOL_TIMEOUT_MINUTES = 30
  DEFAULT_IDLE_TIMEOUT_MINUTES      =  5

  # Connection pool manager - singleton managing all pools
  class ConnectionPoolManager
    Log = ::Log.for("connection_pool_manager")

    @pools : Hash(String, ConnectionPool)
    @mutex : Mutex
    @config : ConnectionPoolingConfig?
    @cleanup_interval : Time::Span
    @running : Atomic(Int32)

    def initialize(config : ConnectionPoolingConfig? = nil)
      @pools = Hash(String, ConnectionPool).new
      @mutex = Mutex.new
      @config = config
      @cleanup_interval = DEFAULT_CLEANUP_INTERVAL_MINUTES.minutes
      @running = Atomic(Int32).new(1)

      # Cleanup fiber'ı başlat
      spawn cleanup_loop

      Log.info { "ConnectionPoolManager started" }
    end

    # Pool key oluştur: scheme://host:port:verify_ssl
    def pool_key(upstream_uri : URI, verify_ssl : Bool) : String
      port = upstream_uri.port || (upstream_uri.scheme == "https" ? 443 : 80)
      "#{upstream_uri.scheme}://#{upstream_uri.host}:#{port}:#{verify_ssl}"
    end

    # Pool al veya oluştur
    def get_pool(
      upstream_uri : URI,
      tls_context : OpenSSL::SSL::Context::Client? = nil,
      verify_ssl : Bool = true,
    ) : ConnectionPool?
      return nil unless @running.get == 1

      key = pool_key(upstream_uri, verify_ssl)

      @mutex.synchronize do
        pool = @pools[key]?

        unless pool
          # Create new pool
          config = @config || default_config
          return nil unless config.enabled

          pool = ConnectionPool.new(
            upstream_uri: upstream_uri,
            tls_context: tls_context,
            pool_size: config.pool_size,
            max_size: config.max_size,
            idle_timeout: parse_timeout(config.idle_timeout),
            health_check: config.health_check
          )

          @pools[key] = pool
          Log.info { "New pool created: #{key}" }
        end

        pool
      end
    end

    # Pool'u kaldır (cleanup için)
    def remove_pool(key : String)
      @mutex.synchronize do
        if pool = @pools.delete(key)
          pool.close_all
          Log.info { "Pool removed: #{key}" }
        end
      end
    end

    # Idle pool'ları temizle
    def cleanup_idle_pools
      return unless @running.get == 1

      @mutex.synchronize do
        now = Time.utc
        idle_pool_timeout = DEFAULT_IDLE_POOL_TIMEOUT_MINUTES.minutes # Remove if pool itself is idle

        pools_to_remove = [] of String

        @pools.each do |key, pool|
          stats = pool.stats
          if last_used_str = stats["last_used"]?.as?(String)
            last_used = Time.parse_rfc3339(last_used_str)

            if (now - last_used) > idle_pool_timeout
              pools_to_remove << key
            end
          end
        end

        pools_to_remove.each do |key|
          remove_pool(key)
        end

        Log.debug { "Idle pool cleanup: #{pools_to_remove.size} pools removed" } if pools_to_remove.size > 0
      end
    end

    # Close all pools
    def shutdown_all
      @running.set(0)

      @mutex.synchronize do
        pool_count = @pools.size
        @pools.each do |key, pool|
          pool.close_all
        end
        @pools.clear

        Log.info { "ConnectionPoolManager shut down: #{pool_count} pools closed" }
      end
    end

    # Pool istatistikleri
    def stats : Hash(String, Hash(String, Int32 | String))
      @mutex.synchronize do
        result = {} of String => Hash(String, Int32 | String)
        @pools.each do |key, pool|
          result[key] = pool.stats
        end
        result
      end
    end

    # Pool sayısı
    def pool_count : Int32
      @mutex.synchronize do
        @pools.size
      end
    end

    private def default_config : ConnectionPoolingConfig
      ConnectionPoolingConfig.new_default
    end

    private def parse_timeout(timeout_str : String) : Time::Span
      # "300s", "5m", "1h" formatlarını parse et
      timeout_str = timeout_str.strip.downcase

      if timeout_str.ends_with?("s")
        seconds = timeout_str[0..-2].to_i
        seconds.seconds
      elsif timeout_str.ends_with?("m")
        minutes = timeout_str[0..-2].to_i
        minutes.minutes
      elsif timeout_str.ends_with?("h")
        hours = timeout_str[0..-2].to_i
        hours.hours
      else
        # Default: saniye olarak kabul et
        timeout_str.to_i.seconds
      end
    rescue
      # Parse error - default value
      DEFAULT_IDLE_TIMEOUT_MINUTES.minutes
    end

    private def cleanup_loop
      loop do
        break unless @running.get == 1
        sleep @cleanup_interval

        cleanup_idle_pools
      end
    end
  end
end
