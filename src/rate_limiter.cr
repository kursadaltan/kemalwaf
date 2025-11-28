require "time"
require "atomic"

module KemalWAF
  # Constants
  DEFAULT_CLEANUP_INTERVAL_SEC       = 300 # 5 minutes
  DEFAULT_CLEANUP_MAX_AGE_MULTIPLIER =   2

  # Rate limit result
  struct RateLimitResult
    property allowed : Bool
    property limit : Int32
    property remaining : Int32
    property reset_at : Time
    property blocked_until : Time?

    def initialize(@allowed, @limit, @remaining, @reset_at, @blocked_until = nil)
    end
  end

  # Endpoint bazlı limit konfigürasyonu
  struct EndpointLimit
    property path_pattern : String
    property limit : Int32
    property window_sec : Int32

    def initialize(@path_pattern : String, @limit : Int32, @window_sec : Int32)
    end

    # Path pattern matching (basit wildcard desteği)
    def matches?(path : String) : Bool
      if @path_pattern.includes?("*")
        # Basit wildcard matching - * karakterini regex'e çevir
        # /api/* -> /api/.* olmalı (sadece /api/ ile başlayan path'ler)
        # * karakterini escape et ve .* ile değiştir
        escaped_pattern = Regex.escape(@path_pattern).gsub("\\*", ".*")
        regex = Regex.new("^#{escaped_pattern}$")
        regex.matches?(path)
      else
        @path_pattern == path
      end
    end
  end

  # IP için rate limit state
  class IPRateLimitState
    @mutex : Mutex
    @requests : Array(Time)
    @window_start : Time
    @blocked_until : Time?

    def initialize(@limit : Int32, @window_sec : Int32)
      @mutex = Mutex.new
      @requests = [] of Time
      @window_start = Time.utc
      @blocked_until = nil
    end

    def check(now : Time) : RateLimitResult
      @mutex.synchronize do
        # Block durumunu kontrol et
        if blocked = @blocked_until
          if now < blocked
            return RateLimitResult.new(
              allowed: false,
              limit: @limit,
              remaining: 0,
              reset_at: blocked,
              blocked_until: blocked
            )
          else
            # Block süresi doldu, temizle
            @blocked_until = nil
            @requests.clear
            @window_start = now
          end
        end

        # Eski istekleri temizle (sliding window)
        @requests.reject! { |req_time| (now - req_time).total_seconds > @window_sec }

        # Window başlangıcını güncelle
        if @requests.empty?
          @window_start = now
        end

        # Mevcut istek sayısını kontrol et
        current_count = @requests.size

        if current_count >= @limit
          # Limit aşıldı
          # Reset zamanını hesapla (en eski istek + window süresi)
          oldest_request = @requests.first?
          reset_at = oldest_request ? oldest_request + @window_sec.seconds : now + @window_sec.seconds

          return RateLimitResult.new(
            allowed: false,
            limit: @limit,
            remaining: 0,
            reset_at: reset_at,
            blocked_until: nil
          )
        end

        # İstek ekle
        @requests << now

        # Reset zamanını hesapla
        oldest_request = @requests.first?
        reset_at = oldest_request ? oldest_request + @window_sec.seconds : now + @window_sec.seconds

        RateLimitResult.new(
          allowed: true,
          limit: @limit,
          remaining: @limit - @requests.size,
          reset_at: reset_at,
          blocked_until: nil
        )
      end
    end

    def block(until_time : Time)
      @mutex.synchronize do
        @blocked_until = until_time
        @requests.clear
      end
    end

    def cleanup(now : Time, max_age_sec : Int32)
      @mutex.synchronize do
        # Eğer block durumu yoksa ve son istekten çok zaman geçtiyse temizle
        if @blocked_until.nil? && !@requests.empty?
          last_request = @requests.last?
          if last_request && (now - last_request).total_seconds > max_age_sec
            @requests.clear
            return true # Cleaned
          end
        end
        false
      end
    end
  end

  # Rate limiter - sliding window algoritması
  class RateLimiter
    Log = ::Log.for("rate_limiter")

    @ip_states : Hash(String, IPRateLimitState)
    @default_limit : Int32
    @default_window_sec : Int32
    @block_duration_sec : Int32
    @endpoint_limits : Array(EndpointLimit)
    @mutex : Mutex
    @cleanup_interval_sec : Int32
    @last_cleanup : Time

    def initialize(
      @default_limit : Int32 = 100,
      @default_window_sec : Int32 = 60,
      @block_duration_sec : Int32 = 300,
    )
      @ip_states = Hash(String, IPRateLimitState).new
      @endpoint_limits = [] of EndpointLimit
      @mutex = Mutex.new
      @cleanup_interval_sec = DEFAULT_CLEANUP_INTERVAL_SEC
      @last_cleanup = Time.utc

      # Cleanup fiber'ı başlat
      spawn cleanup_loop
    end

    # Endpoint limit ekle
    def add_endpoint_limit(path_pattern : String, limit : Int32, window_sec : Int32)
      @mutex.synchronize do
        @endpoint_limits << EndpointLimit.new(path_pattern, limit, window_sec)
        Log.info { "Endpoint limit eklendi: #{path_pattern} -> #{limit}/#{window_sec}s" }
      end
    end

    # IP için rate limit kontrolü
    def check(ip : String, path : String) : RateLimitResult
      now = Time.utc

      # Endpoint-specific limit var mı kontrol et
      endpoint_limit = find_endpoint_limit(path)
      limit = endpoint_limit ? endpoint_limit.limit : @default_limit
      window_sec = endpoint_limit ? endpoint_limit.window_sec : @default_window_sec

      # State key'i oluştur: IP + endpoint pattern (eğer varsa) veya "default"
      state_key = if endpoint_limit
                    "#{ip}:#{endpoint_limit.path_pattern}"
                  else
                    "#{ip}:default"
                  end

      # IP state'i al veya oluştur
      state = get_or_create_state(state_key, limit, window_sec)

      # Rate limit kontrolü
      result = state.check(now)

      # Periyodik cleanup
      if (now - @last_cleanup).total_seconds > @cleanup_interval_sec
        spawn { cleanup_old_states(now) }
        @last_cleanup = now
      end

      result
    end

    # IP'yi geçici olarak blokla (tüm endpoint'ler için)
    def block_ip(ip : String, duration_sec : Int32? = nil)
      duration = duration_sec || @block_duration_sec
      block_until = Time.utc + duration.seconds

      @mutex.synchronize do
        # IP ile başlayan tüm state'leri bul ve blokla
        @ip_states.each do |key, state|
          if key.starts_with?("#{ip}:")
            state.block(block_until)
          end
        end
        # Eğer hiç state yoksa, default state oluştur
        if !@ip_states.any? { |key, _| key.starts_with?("#{ip}:") }
          state = IPRateLimitState.new(@default_limit, @default_window_sec)
          state.block(block_until)
          @ip_states["#{ip}:default"] = state
        end
      end

      Log.warn { "IP bloklandı: #{ip} -> #{block_until}" }
    end

    # IP block'unu kaldır (tüm endpoint'ler için)
    def unblock_ip(ip : String)
      @mutex.synchronize do
        @ip_states.each do |key, state|
          if key.starts_with?("#{ip}:")
            state.block(Time.utc - 1.second) # Geçmiş bir zaman set et, böylece block kalkar
          end
        end
      end
    end

    # Rate limit header'larını response'a ekle
    def set_headers(response : HTTP::Server::Response, result : RateLimitResult)
      response.headers["X-RateLimit-Limit"] = result.limit.to_s
      response.headers["X-RateLimit-Remaining"] = result.remaining.to_s
      response.headers["X-RateLimit-Reset"] = result.reset_at.to_unix.to_s

      if blocked_until = result.blocked_until
        response.headers["X-RateLimit-Blocked-Until"] = blocked_until.to_unix.to_s
      end
    end

    private def find_endpoint_limit(path : String) : EndpointLimit?
      @endpoint_limits.find { |limit| limit.matches?(path) }
    end

    private def get_or_create_state(state_key : String, limit : Int32, window_sec : Int32) : IPRateLimitState
      @mutex.synchronize do
        state = @ip_states[state_key]?
        unless state
          state = IPRateLimitState.new(limit, window_sec)
          @ip_states[state_key] = state
        else
          # State varsa limit ve window'u güncelle (eğer değiştiyse)
          # Not: Mevcut state'in limit'i değişebilir ama bu normal
        end
        state
      end
    end

    private def cleanup_loop
      loop do
        sleep @cleanup_interval_sec.seconds
        cleanup_old_states(Time.utc)
      end
    end

    private def cleanup_old_states(now : Time)
      @mutex.synchronize do
        max_age = @cleanup_interval_sec * DEFAULT_CLEANUP_MAX_AGE_MULTIPLIER
        ips_to_remove = [] of String

        @ip_states.each do |ip, state|
          if state.cleanup(now, max_age)
            # If state is completely cleaned and no block status, can be removed
            ips_to_remove << ip
          end
        end

        ips_to_remove.each do |ip|
          @ip_states.delete(ip)
        end

        Log.debug { "Rate limiter cleanup: #{ips_to_remove.size} IP states cleaned" } if ips_to_remove.size > 0
      end
    end
  end
end
