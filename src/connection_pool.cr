require "http/client"
require "uri"
require "openssl"
require "atomic"

module KemalWAF
  # Constants
  DEFAULT_POOL_ACQUIRE_TIMEOUT_MS  = 100
  DEFAULT_READ_TIMEOUT_SEC         =  30
  DEFAULT_CONNECT_TIMEOUT_SEC      =  10
  DEFAULT_IDLE_TIMEOUT_MINUTES     =   5
  DEFAULT_CLEANUP_INTERVAL_MINUTES =   1
  DEFAULT_POOL_FILL_DELAY_MS       =  10
  CRITICAL_POOL_CONNECTIONS        =  10

  # Connection metadata for connection pool
  struct PooledConnection
    property client : HTTP::Client
    property created_at : Time
    property last_used : Time
    property use_count : Int32

    def initialize(@client : HTTP::Client)
      @created_at = Time.utc
      @last_used = Time.utc
      @use_count = 0
    end

    def mark_used
      @last_used = Time.utc
      @use_count += 1
    end

    def idle_time : Time::Span
      Time.utc - @last_used
    end

    def is_idle?(timeout : Time::Span) : Bool
      idle_time > timeout
    end
  end

  # Connection pool - her upstream URI + TLS context kombinasyonu için
  class ConnectionPool
    Log = ::Log.for("connection_pool")

    @pool : Channel(PooledConnection?)
    @upstream_uri : URI
    @tls_context : OpenSSL::SSL::Context::Client?
    @pool_size : Int32
    @max_size : Int32
    @idle_timeout : Time::Span
    @health_check : Bool
    @created_at : Time
    @last_used : Time
    @last_used_mutex : Mutex
    @current_size : Atomic(Int32)
    @mutex : Mutex
    @running : Atomic(Int32)

    def initialize(
      upstream_uri : URI,
      tls_context : OpenSSL::SSL::Context::Client? = nil,
      pool_size : Int32 = 100,
      max_size : Int32 = 200,
      idle_timeout : Time::Span = DEFAULT_IDLE_TIMEOUT_MINUTES.minutes,
      health_check : Bool = true,
    )
      @upstream_uri = upstream_uri
      @tls_context = tls_context
      @pool_size = pool_size
      @max_size = max_size
      @idle_timeout = idle_timeout
      @health_check = health_check
      @created_at = Time.utc
      @last_used = Time.utc
      @last_used_mutex = Mutex.new
      @current_size = Atomic(Int32).new(0)
      @mutex = Mutex.new
      @running = Atomic(Int32).new(1)

      # Channel oluştur (buffered - non-blocking send)
      @pool = Channel(PooledConnection?).new(@pool_size)

      # Fill initial pool (optimized - first connections immediately)
      # Strategy: Create first N connections immediately for zero-latency critical path,
      # then fill the rest in background to avoid startup overload
      spawn fill_initial_pool

      # Cleanup fiber'ı başlat
      spawn cleanup_loop

      Log.info { "ConnectionPool created: #{upstream_uri} (size: #{pool_size}, max: #{max_size})" }
    end

    # Get connection from pool (with timeout)
    def acquire(timeout : Time::Span = DEFAULT_POOL_ACQUIRE_TIMEOUT_MS.milliseconds) : HTTP::Client?
      return nil unless @running.get == 1

      pooled_conn = nil

      # Channel'dan connection al (timeout ile)
      select
      when conn = @pool.receive
        pooled_conn = conn
        # Connection alındı, current_size'i azalt
        @current_size.sub(1)
      when timeout(timeout)
        # Timeout - pool'dan connection alınamadı
        Log.debug { "Connection acquire timeout, new connection will be created" }
        return create_new_connection
      end

      return nil unless pooled_conn

      # Idle timeout kontrolü
      if pooled_conn.is_idle?(@idle_timeout)
        Log.debug { "Connection hit idle timeout, closing" }
        begin
          pooled_conn.client.close
        rescue
          # Ignore close errors
        end
        # current_size already decreased (above), create new connection
        return create_new_connection
      end

      # Health check (simple - is connection still open?)
      if @health_check && !is_connection_healthy?(pooled_conn.client)
        Log.debug { "Connection unhealthy, closing" }
        begin
          pooled_conn.client.close
        rescue
          # Ignore close errors
        end
        # current_size already decreased (above), create new connection
        return create_new_connection
      end

      pooled_conn.mark_used
      @last_used_mutex.synchronize do
        @last_used = Time.utc
      end
      pooled_conn.client
    end

    # Connection'ı pool'a geri ver
    def release(client : HTTP::Client?)
      return unless client
      return unless @running.get == 1

      # Max size kontrolü
      current = @current_size.get
      if current >= @max_size
        # Pool full, close connection
        Log.debug { "Pool full (#{current}/#{@max_size}), closing connection" }
        begin
          client.close
        rescue
          # Ignore close errors
        end
        return
      end

      # Return connection to pool (buffered channel - non-blocking)
      pooled_conn = PooledConnection.new(client)
      @pool.send(pooled_conn) # Buffered channel, blocking olmaz
      @current_size.add(1)
    end

    # Create new connection (for fallback)
    def create_new_connection : HTTP::Client?
      return nil unless @running.get == 1

      begin
        client = HTTP::Client.new(@upstream_uri, tls: @tls_context)
        client.read_timeout = DEFAULT_READ_TIMEOUT_SEC.seconds
        client.connect_timeout = DEFAULT_CONNECT_TIMEOUT_SEC.seconds
        client
      rescue ex
        Log.error { "Failed to create new connection: #{ex.message}" }
        nil
      end
    end

    # Close all connections
    def close_all
      @running.set(0)

      @mutex.synchronize do
        closed_count = 0
        loop do
          select
          when conn = @pool.receive?
            if conn
              begin
                conn.client.close
                closed_count += 1
              rescue
                # Ignore close errors
              end
            else
              break
            end
          else
            break
          end
        end

        Log.info { "ConnectionPool closed: #{closed_count} connections closed" }
      end
    end

    # Pool istatistikleri
    def stats : Hash(String, Int32 | String)
      {
        "current_size" => @current_size.get,
        "pool_size"    => @pool_size,
        "max_size"     => @max_size,
        "upstream"     => @upstream_uri.to_s,
        "created_at"   => @created_at.to_rfc3339,
        "last_used"    => @last_used_mutex.synchronize { @last_used.to_rfc3339 },
      }
    end

    private def fill_initial_pool
      # Create first connections immediately (for critical path - zero latency)
      critical_count = [CRITICAL_POOL_CONNECTIONS, @pool_size].min
      critical_count.times do |i|
        break unless @running.get == 1

        conn = create_new_connection
        if conn
          pooled_conn = PooledConnection.new(conn)
          @pool.send(pooled_conn) # Buffered channel, non-blocking
          @current_size.add(1)
        end
      end

      Log.info { "Critical pool connections created: #{@current_size.get} connections" }

      # Fill the rest slowly in background (to prevent overload)
      if @pool_size > critical_count
        spawn do
          (critical_count...@pool_size).each do |i|
            break unless @running.get == 1

            conn = create_new_connection
            if conn
              pooled_conn = PooledConnection.new(conn)
              select
              when @pool.send(pooled_conn)
                @current_size.add(1)
              else
                # Channel full, close connection
                begin
                  conn.close
                rescue
                end
              end
            end

            # Brief wait between each connection (to prevent overload)
            sleep DEFAULT_POOL_FILL_DELAY_MS.milliseconds if i < @pool_size - 1
          end

          Log.info { "Initial pool filled: #{@current_size.get} connections" }
        end
      end
    end

    private def cleanup_loop
      loop do
        break unless @running.get == 1
        sleep DEFAULT_CLEANUP_INTERVAL_MINUTES.minute # Cleanup every minute

        cleanup_idle_connections
      end
    end

    private def cleanup_idle_connections
      @mutex.synchronize do
        # Check all connections in channel
        # Note: Need to take from channel and put back (no peek)
        connections_to_check = [] of PooledConnection?
        current_size = @current_size.get

        # Get all connections
        current_size.times do
          select
          when conn = @pool.receive?
            connections_to_check << conn
          else
            break
          end
        end

        # Close idle ones, return others
        idle_count = 0
        connections_to_check.each do |conn|
          if conn && conn.is_idle?(@idle_timeout)
            # Close idle connection
            begin
              conn.client.close
            rescue
            end
            idle_count += 1
            @current_size.sub(1)
          else
            # Return connection
            select
            when @pool.send(conn)
              # Successfully returned
            else
              # Channel full, close connection
              if conn
                begin
                  conn.client.close
                rescue
                end
                @current_size.sub(1)
              end
            end
          end
        end

        Log.debug { "Cleanup completed: #{idle_count} idle connections closed" } if idle_count > 0
      end
    end

    private def is_connection_healthy?(client : HTTP::Client) : Bool
      # Basit health check: client'ın hala açık olup olmadığını kontrol et
      # HTTP::Client'ın internal state'ini kontrol edemiyoruz, bu yüzden
      # sadece client nil değilse healthy kabul ediyoruz
      # Gerçek health check için bir test request yapılabilir ama bu pahalı
      true
    end
  end
end
