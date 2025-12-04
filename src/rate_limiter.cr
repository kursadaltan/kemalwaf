require "time"
require "atomic"

module KemalWAF
  # =============================================================================
  # LOCK-FREE RATE LIMITER IMPLEMENTATION
  # =============================================================================
  # High-performance rate limiting using:
  # - Atomic counters (no mutex in hotpath)
  # - Ring-buffer sliding window (8 slots)
  # - Sharded state map (reduced lock contention)
  # - Lock-free counter eviction
  # =============================================================================

  # Constants
  RING_BUFFER_SLOTS             = 8
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
  # Lock-Free Sliding Window Counter
  # =============================================================================
  # Uses atomic operations for thread-safe counting without locks
  # Ring buffer with 8 slots for fine-grained time windows
  # =============================================================================
  class SlidingWindowCounter
    # Ring buffer slots - each slot holds count for a time segment
    @slots : StaticArray(Atomic(Int64), RING_BUFFER_SLOTS)
    # Timestamps for each slot (in seconds since epoch)
    @slot_timestamps : StaticArray(Atomic(Int64), RING_BUFFER_SLOTS)
    # Block status
    @blocked_until : Atomic(Int64) # Unix timestamp, 0 if not blocked
    # Configuration
    @limit : Int32
    @window_sec : Int32
    @slot_duration_sec : Int32

    def initialize(@limit : Int32, @window_sec : Int32)
      @slot_duration_sec = @window_sec // RING_BUFFER_SLOTS
      @slot_duration_sec = 1 if @slot_duration_sec < 1

      # Initialize slots
      @slots = StaticArray(Atomic(Int64), RING_BUFFER_SLOTS).new { Atomic(Int64).new(0_i64) }
      @slot_timestamps = StaticArray(Atomic(Int64), RING_BUFFER_SLOTS).new { Atomic(Int64).new(0_i64) }
      @blocked_until = Atomic(Int64).new(0_i64)
    end

    # Check rate limit (lock-free)
    def check(now : Time) : RateLimitResult
      now_unix = now.to_unix

      # Check if blocked
      blocked = @blocked_until.get
      if blocked > 0 && now_unix < blocked
        return RateLimitResult.new(
          allowed: false,
          limit: @limit,
          remaining: 0,
          reset_at: Time.unix(blocked),
          blocked_until: Time.unix(blocked)
        )
      elsif blocked > 0 && now_unix >= blocked
        # Block expired, reset
        @blocked_until.compare_and_set(blocked, 0_i64)
        clear_all_slots
      end

      # Calculate current slot index
      slot_idx = (now_unix // @slot_duration_sec) % RING_BUFFER_SLOTS

      # Get current slot timestamp
      slot_ts = @slot_timestamps[slot_idx].get

      # If slot is from a different time period, reset it
      expected_ts = (now_unix // @slot_duration_sec) * @slot_duration_sec
      if slot_ts != expected_ts
        # Try to claim this slot for current time period
        if @slot_timestamps[slot_idx].compare_and_set(slot_ts, expected_ts)
          @slots[slot_idx].set(0_i64)
        end
      end

      # Count requests in all valid slots (within window)
      total_count = count_requests_in_window(now_unix)

      if total_count >= @limit
        # Calculate reset time (oldest slot + window)
        oldest_ts = find_oldest_valid_slot_timestamp(now_unix)
        reset_at = Time.unix(oldest_ts + @window_sec)

        return RateLimitResult.new(
          allowed: false,
          limit: @limit,
          remaining: 0,
          reset_at: reset_at,
          blocked_until: nil
        )
      end

      # Increment current slot atomically
      @slots[slot_idx].add(1_i64)

      # Calculate remaining and reset time
      remaining = @limit - (total_count.to_i32 + 1)
      remaining = 0 if remaining < 0
      oldest_ts = find_oldest_valid_slot_timestamp(now_unix)
      reset_at = Time.unix(oldest_ts + @window_sec)

      RateLimitResult.new(
        allowed: true,
        limit: @limit,
        remaining: remaining,
        reset_at: reset_at,
        blocked_until: nil
      )
    end

    # Block until specified time
    def block(until_time : Time)
      @blocked_until.set(until_time.to_unix)
      clear_all_slots
    end

    # Clear all slots
    def clear_all_slots
      RING_BUFFER_SLOTS.times do |i|
        @slots[i].set(0_i64)
        @slot_timestamps[i].set(0_i64)
      end
    end

    # Check if this counter should be evicted (lock-free)
    def should_evict?(now_unix : Int64, max_age_sec : Int32) : Bool
      # If blocked, don't evict
      return false if @blocked_until.get > 0

      # Check if all slots are stale
      RING_BUFFER_SLOTS.times do |i|
        slot_ts = @slot_timestamps[i].get
        if slot_ts > 0 && (now_unix - slot_ts) < max_age_sec
          return false
        end
      end

      true
    end

    # Count requests within the sliding window
    private def count_requests_in_window(now_unix : Int64) : Int64
      total = 0_i64
      window_start = now_unix - @window_sec

      RING_BUFFER_SLOTS.times do |i|
        slot_ts = @slot_timestamps[i].get
        if slot_ts >= window_start
          total += @slots[i].get
        end
      end

      total
    end

    # Find oldest valid slot timestamp for reset calculation
    private def find_oldest_valid_slot_timestamp(now_unix : Int64) : Int64
      oldest = now_unix
      window_start = now_unix - @window_sec

      RING_BUFFER_SLOTS.times do |i|
        slot_ts = @slot_timestamps[i].get
        if slot_ts >= window_start && slot_ts > 0 && slot_ts < oldest
          oldest = slot_ts
        end
      end

      oldest
    end
  end

  # =============================================================================
  # Sharded IP State Map
  # =============================================================================
  # Reduces lock contention by distributing IP states across multiple shards
  # Each shard has its own lock, so concurrent requests to different IPs
  # don't block each other
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
      # Simple hash-based sharding
      (key.hash % SHARD_COUNT).to_i32
    end

    # Get or create counter for key
    def get_or_create(key : String, limit : Int32? = nil, window_sec : Int32? = nil) : SlidingWindowCounter
      idx = shard_index(key)
      
      # Fast path: check without lock
      counter = @shards[idx][key]?
      return counter if counter

      # Slow path: create with lock
      @shard_locks[idx].synchronize do
        # Double-check after acquiring lock
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
      @shards[idx][key]?
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
      now_unix = now.to_unix
      start_time = Time.monotonic
      removed = 0

      SHARD_COUNT.times do |idx|
        # Check time budget
        elapsed = (Time.monotonic - start_time).total_milliseconds
        break if elapsed >= max_duration_ms

        keys_to_remove = [] of String

        @shard_locks[idx].synchronize do
          @shards[idx].each do |key, counter|
            if counter.should_evict?(now_unix, max_age_sec)
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
        total += @shards[idx].size
      end
      total
    end
  end

  # =============================================================================
  # Lock-Free Rate Limiter
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

    # Check rate limit (lock-free in hotpath)
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

      # Get or create counter (lock-free after initial creation)
      counter = @ip_states.get_or_create(state_key, limit, window_sec)

      # Check rate limit (completely lock-free)
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
