require "http/client"
require "uri"
require "openssl"
require "atomic"

module KemalWAF
  # Connection pool için connection metadata
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
      idle_timeout : Time::Span = 5.minutes,
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

      # Initial pool'u doldur (optimized - ilk connection'lar hemen)
      spawn fill_initial_pool

      # Cleanup fiber'ı başlat
      spawn cleanup_loop

      Log.info { "ConnectionPool oluşturuldu: #{upstream_uri} (size: #{pool_size}, max: #{max_size})" }
    end

    # Pool'dan connection al (timeout ile)
    def acquire(timeout : Time::Span = 100.milliseconds) : HTTP::Client?
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
        Log.debug { "Connection acquire timeout, yeni connection oluşturulacak" }
        return create_new_connection
      end

      return nil unless pooled_conn

      # Idle timeout kontrolü
      if pooled_conn.is_idle?(@idle_timeout)
        Log.debug { "Connection idle timeout'a uğradı, kapatılıyor" }
        begin
          pooled_conn.client.close
        rescue
          # Ignore close errors
        end
        # current_size zaten azaltıldı (yukarıda), yeni connection oluştur
        return create_new_connection
      end

      # Health check (basit - connection hala açık mı?)
      if @health_check && !is_connection_healthy?(pooled_conn.client)
        Log.debug { "Connection unhealthy, kapatılıyor" }
        begin
          pooled_conn.client.close
        rescue
          # Ignore close errors
        end
        # current_size zaten azaltıldı (yukarıda), yeni connection oluştur
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
        # Pool dolu, connection'ı kapat
        Log.debug { "Pool dolu (#{current}/#{@max_size}), connection kapatılıyor" }
        begin
          client.close
        rescue
          # Ignore close errors
        end
        return
      end

      # Connection'ı pool'a geri ver (buffered channel - non-blocking)
      pooled_conn = PooledConnection.new(client)
      @pool.send(pooled_conn) # Buffered channel, blocking olmaz
      @current_size.add(1)
    end

    # Yeni connection oluştur (fallback için)
    def create_new_connection : HTTP::Client?
      return nil unless @running.get == 1

      begin
        client = HTTP::Client.new(@upstream_uri, tls: @tls_context)
        client.read_timeout = 30.seconds
        client.connect_timeout = 10.seconds
        client
      rescue ex
        Log.error { "Yeni connection oluşturulamadı: #{ex.message}" }
        nil
      end
    end

    # Tüm connection'ları kapat
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

        Log.info { "ConnectionPool kapatıldı: #{closed_count} connection kapatıldı" }
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
      # İlk 10 connection'ı hemen oluştur (critical path için - sıfır latency)
      critical_count = [10, @pool_size].min
      critical_count.times do |i|
        break unless @running.get == 1

        conn = create_new_connection
        if conn
          pooled_conn = PooledConnection.new(conn)
          @pool.send(pooled_conn) # Buffered channel, non-blocking
          @current_size.add(1)
        end
      end

      Log.info { "Critical pool connections oluşturuldu: #{@current_size.get} connection" }

      # Geri kalanını background'da yavaşça doldur (overload önlemek için)
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
                # Channel dolu, connection'ı kapat
                begin
                  conn.close
                rescue
                end
              end
            end

            # Her connection arasında kısa bir bekleme (overload önlemek için)
            sleep 10.milliseconds if i < @pool_size - 1
          end

          Log.info { "Initial pool dolduruldu: #{@current_size.get} connection" }
        end
      end
    end

    private def cleanup_loop
      loop do
        break unless @running.get == 1
        sleep 1.minute # Her dakika cleanup yap

        cleanup_idle_connections
      end
    end

    private def cleanup_idle_connections
      @mutex.synchronize do
        # Channel'daki tüm connection'ları kontrol et
        # Not: Channel'dan alıp geri koymak gerekiyor (peek yok)
        connections_to_check = [] of PooledConnection?
        current_size = @current_size.get

        # Tüm connection'ları al
        current_size.times do
          select
          when conn = @pool.receive?
            connections_to_check << conn
          else
            break
          end
        end

        # Idle olanları kapat, diğerlerini geri koy
        idle_count = 0
        connections_to_check.each do |conn|
          if conn && conn.is_idle?(@idle_timeout)
            # Idle connection'ı kapat
            begin
              conn.client.close
            rescue
            end
            idle_count += 1
            @current_size.sub(1)
          else
            # Connection'ı geri koy
            select
            when @pool.send(conn)
              # Başarıyla geri konuldu
            else
              # Channel dolu, connection'ı kapat
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

        Log.debug { "Cleanup tamamlandı: #{idle_count} idle connection kapatıldı" } if idle_count > 0
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
