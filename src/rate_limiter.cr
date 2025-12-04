require "time"
require "atomic"

module KemalWAF
  # =============================================================================
  # LOCK-FREE RATE LIMITER IMPLEMENTATION
  # =============================================================================
  # High-performance rate limiting using:
  # - Sharded state map (reduced lock contention)
  # - Per-shard mutex (fine-grained locking)
  # - Sliding window algorithm
  # - Lock-free cleanup eviction
  # =============================================================================

  # Constants
  SHARD_COUNT                   = 64
  DEFAULT_CLEANUP_INTERVAL_SEC  = 300 # 5 minutes
  DEFAULT_CLEANUP_MAX_AGE_MULTIPLIER = 2
  EVICTION_MAX_DURATION_MS      = 2 # Max 2ms for eviction

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

    def matches?(path : String) : Bool
      if @path_pattern.includes?("*")
        escaped_pattern = Regex.escape(@path_pattern).gsub("\\*", ".*")
        regex = Regex.new("^#{escaped_pattern}$")
        regex.matches?(path)
      else
        @path_pattern == path
      end
    end
  end

  # =============================================================================
  # Sliding Window Counter (Simple, Correct Implementation)
  # =============================================================================
  # Uses array of timestamps for accurate sliding window
  # =============================================================================
  class SlidingWindowCounter
    @requests : Array(Time)
    @blocked_until : Time?
    @limit : Int32
    @window_sec : Int32
    @mutex : Mutex

    def initialize(@limit : Int32, @window_sec : Int32)
      @requests = [] of Time
      @blocked_until = nil
      @mutex = Mutex.new
    end

    # Check rate limit
    def check(now : Time) : RateLimitResult
      @mutex.synchronize do
        # Check if blocked
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
            # Block expired, reset
            @blocked_until = nil
            @requests.clear
          end
        end

        # Clean old requests (outside window)
        window_start = now - @window_sec.seconds
        @requests.reject! { |req_time| req_time < window_start }

        # Check limit
        if @requests.size >= @limit
          # Calculate reset time
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

        # Add request
        @requests << now

        # Calculate remaining and reset time
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

    # Block until specified time
    def block(until_time : Time)
      @mutex.synchronize do
        @blocked_until = until_time
        @requests.clear
      end
    end

    # Check if this counter should be evicted
    def should_evict?(now : Time, max_age_sec : Int32) : Bool
      @mutex.synchronize do
        return false if @blocked_until

        if @requests.empty?
          return true
        end

        last_request = @requests.last?
        if last_request && (now - last_request).total_seconds > max_age_sec
          return true
        end

        false
      end
    end

    # Cleanup old requests
    def cleanup(now : Time) : Bool
      @mutex.synchronize do
        return false if @blocked_until

        window_start = now - @window_sec.seconds
        old_size = @requests.size
        @requests.reject! { |req_time| req_time < window_start }
        @requests.size < old_size
      end
    end
  end

  # =============================================================================
  # Sharded IP State Map
  # =============================================================================
  # Reduces lock contention by distributing IP states across multiple shards
  # =============================================================================
  class ShardedIPStateMap
    @shards : Array(Hash(String, SlidingWindowCounter))
    @shard_locks : Array(Mutex)
    @default_limit : Int32
    @default_window_sec : Int32

    def initialize(@default_limit : Int32, @default_window_sec : Int32)
      @shards = Array(Hash(String, SlidingWindowCounter)).new(SHARD_COUNT) do
        Hash(String, SlidingWindowCounter).new
      end
      @shard_locks = Array(Mutex).new(SHARD_COUNT) { Mutex.new }
    end

    # Get shard index for a key using hash
    private def shard_index(key : String) : Int32
      (key.hash % SHARD_COUNT).to_i32
    end

    # Get or create counter for key
    def get_or_create(key : String, limit : Int32? = nil, window_sec : Int32? = nil) : SlidingWindowCounter
      idx = shard_index(key)
      
      @shard_locks[idx].synchronize do
        counter = @shards[idx][key]?
        return counter if counter

        # Create new counter
        new_limit = limit || @default_limit
        new_window = window_sec || @default_window_sec
        counter = SlidingWindowCounter.new(new_limit, new_window)
        @shards[idx][key] = counter
        counter
      end
    end

    # Get existing counter (returns nil if not found)
    def get(key : String) : SlidingWindowCounter?
      idx = shard_index(key)
      @shard_locks[idx].synchronize do
        @shards[idx][key]?
      end
    end

    # Delete counter
    def delete(key : String)
      idx = shard_index(key)
      @shard_locks[idx].synchronize do
        @shards[idx].delete(key)
      end
    end

    # Iterate over all keys matching prefix
    def each_with_prefix(prefix : String, &block : String, SlidingWindowCounter -> )
      SHARD_COUNT.times do |idx|
        @shard_locks[idx].synchronize do
          @shards[idx].each do |key, counter|
            if key.starts_with?(prefix)
              yield key, counter
            end
          end
        end
      end
    end

    # Cleanup stale entries (with time budget)
    def cleanup(now : Time, max_age_sec : Int32, max_duration_ms : Int32 = EVICTION_MAX_DURATION_MS) : Int32
      start_time = Time.monotonic
      removed = 0

      SHARD_COUNT.times do |idx|
        # Check time budget
        elapsed = (Time.monotonic - start_time).total_milliseconds
        break if elapsed >= max_duration_ms

        keys_to_remove = [] of String

        @shard_locks[idx].synchronize do
          @shards[idx].each do |key, counter|
            if counter.should_evict?(now, max_age_sec)
              keys_to_remove << key
            end
          end

          keys_to_remove.each do |key|
            @shards[idx].delete(key)
            removed += 1
          end
        end
      end

      removed
    end

    # Get total count of entries
    def size : Int32
      total = 0
      SHARD_COUNT.times do |idx|
        @shard_locks[idx].synchronize do
          total += @shards[idx].size
        end
      end
      total
    end
  end

  # =============================================================================
  # Rate Limiter with Sharded State Map
  # =============================================================================
  class RateLimiter
    Log = ::Log.for("rate_limiter")

    @ip_states : ShardedIPStateMap
    @default_limit : Int32
    @default_window_sec : Int32
    @block_duration_sec : Int32
    @endpoint_limits : Array(EndpointLimit)
    @endpoint_limits_mutex : Mutex
    @cleanup_interval_sec : Int32
    @last_cleanup : Atomic(Int64)

    def initialize(
      @default_limit : Int32 = 100,
      @default_window_sec : Int32 = 60,
      @block_duration_sec : Int32 = 300,
    )
      @ip_states = ShardedIPStateMap.new(@default_limit, @default_window_sec)
      @endpoint_limits = [] of EndpointLimit
      @endpoint_limits_mutex = Mutex.new
      @cleanup_interval_sec = DEFAULT_CLEANUP_INTERVAL_SEC
      @last_cleanup = Atomic(Int64).new(Time.utc.to_unix)

      # Start cleanup fiber
      spawn cleanup_loop
    end

    # Add endpoint limit
    def add_endpoint_limit(path_pattern : String, limit : Int32, window_sec : Int32)
      @endpoint_limits_mutex.synchronize do
        @endpoint_limits << EndpointLimit.new(path_pattern, limit, window_sec)
        Log.info { "Endpoint limit added: #{path_pattern} -> #{limit}/#{window_sec}s" }
      end
    end

    # Check rate limit
    def check(ip : String, path : String) : RateLimitResult
      now = Time.utc
      now_unix = now.to_unix

      # Find endpoint-specific limit
      endpoint_limit = find_endpoint_limit(path)
      limit = endpoint_limit ? endpoint_limit.limit : @default_limit
      window_sec = endpoint_limit ? endpoint_limit.window_sec : @default_window_sec

      # Create state key
      state_key = if endpoint_limit
                    "#{ip}:#{endpoint_limit.path_pattern}"
                  else
                    "#{ip}:default"
                  end

      # Get or create counter
      counter = @ip_states.get_or_create(state_key, limit, window_sec)

      # Check rate limit
      result = counter.check(now)

      # Trigger cleanup if needed (non-blocking)
      last_cleanup = @last_cleanup.get
      if (now_unix - last_cleanup) > @cleanup_interval_sec
        if @last_cleanup.compare_and_set(last_cleanup, now_unix)
          spawn { cleanup_old_states(now) }
        end
      end

      result
    end

    # Block IP temporarily
    def block_ip(ip : String, duration_sec : Int32? = nil)
      duration = duration_sec || @block_duration_sec
      block_until = Time.utc + duration.seconds

      # Block all counters for this IP
      @ip_states.each_with_prefix("#{ip}:") do |key, counter|
        counter.block(block_until)
      end

      # Create default counter if none exists
      counter = @ip_states.get("#{ip}:default")
      unless counter
        counter = @ip_states.get_or_create("#{ip}:default")
      end
      counter.block(block_until)

      Log.warn { "IP blocked: #{ip} -> #{block_until}" }
    end

    # Unblock IP
    def unblock_ip(ip : String)
      past_time = Time.utc - 1.second
      @ip_states.each_with_prefix("#{ip}:") do |key, counter|
        counter.block(past_time)
      end
    end

    # Set rate limit headers
    def set_headers(response : HTTP::Server::Response, result : RateLimitResult)
      response.headers["X-RateLimit-Limit"] = result.limit.to_s
      response.headers["X-RateLimit-Remaining"] = result.remaining.to_s
      response.headers["X-RateLimit-Reset"] = result.reset_at.to_unix.to_s

      if blocked_until = result.blocked_until
        response.headers["X-RateLimit-Blocked-Until"] = blocked_until.to_unix.to_s
      end
    end

    # Get statistics
    def stats : NamedTuple(active_counters: Int32, default_limit: Int32, default_window_sec: Int32)
      {
        active_counters: @ip_states.size,
        default_limit: @default_limit,
        default_window_sec: @default_window_sec
      }
    end

    private def find_endpoint_limit(path : String) : EndpointLimit?
      @endpoint_limits_mutex.synchronize do
        @endpoint_limits.find { |limit| limit.matches?(path) }
      end
    end

    private def cleanup_loop
      loop do
        sleep @cleanup_interval_sec.seconds
        cleanup_old_states(Time.utc)
      end
    end

    private def cleanup_old_states(now : Time)
      max_age = @cleanup_interval_sec * DEFAULT_CLEANUP_MAX_AGE_MULTIPLIER
      removed = @ip_states.cleanup(now, max_age, EVICTION_MAX_DURATION_MS)
      Log.debug { "Rate limiter cleanup: #{removed} counters removed" } if removed > 0
    end
  end
end
