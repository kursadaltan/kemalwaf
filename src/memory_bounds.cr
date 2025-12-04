require "atomic"

module KemalWAF
  # =============================================================================
  # MEMORY BOUNDS IMPLEMENTATION
  # =============================================================================
  # Module-level memory limits with graceful degradation:
  # - Rate limiter: 50 MB
  # - Challenge cache: 20 MB
  # - Rule engine: 5 MB
  # - Connection pool: 10 MB
  # - MMDB/GeoIP: 80 MB
  # =============================================================================

  # Memory limit constants (in bytes)
  module MemoryLimits
    RATE_LIMITER_BYTES    = 50_i64 * 1024 * 1024 # 50 MB
    CHALLENGE_CACHE_BYTES = 20_i64 * 1024 * 1024 # 20 MB
    RULE_ENGINE_BYTES     = 5_i64 * 1024 * 1024  #  5 MB
    CONNECTION_POOL_BYTES = 10_i64 * 1024 * 1024 # 10 MB
    GEOIP_BYTES           = 80_i64 * 1024 * 1024 # 80 MB

    TOTAL_WAF_BYTES = RATE_LIMITER_BYTES + CHALLENGE_CACHE_BYTES +
                      RULE_ENGINE_BYTES + CONNECTION_POOL_BYTES + GEOIP_BYTES
  end

  # Module types for memory tracking
  enum MemoryModule
    RateLimiter
    ChallengeCache
    RuleEngine
    ConnectionPool
    GeoIP
    Other
  end

  # =============================================================================
  # Memory Usage Tracker
  # =============================================================================
  # Tracks memory usage per module with atomic counters
  # Provides graceful degradation when limits are exceeded
  # =============================================================================
  class MemoryTracker
    Log = ::Log.for("memory_tracker")

    # Per-module usage tracking
    @rate_limiter_bytes : Atomic(Int64)
    @challenge_cache_bytes : Atomic(Int64)
    @rule_engine_bytes : Atomic(Int64)
    @connection_pool_bytes : Atomic(Int64)
    @geoip_bytes : Atomic(Int64)
    @other_bytes : Atomic(Int64)

    # Degradation callbacks
    @degradation_callbacks : Hash(MemoryModule, Proc(Int64, Nil))

    # Singleton instance
    @@instance : MemoryTracker?

    def self.instance : MemoryTracker
      @@instance ||= new
    end

    private def initialize
      @rate_limiter_bytes = Atomic(Int64).new(0_i64)
      @challenge_cache_bytes = Atomic(Int64).new(0_i64)
      @rule_engine_bytes = Atomic(Int64).new(0_i64)
      @connection_pool_bytes = Atomic(Int64).new(0_i64)
      @geoip_bytes = Atomic(Int64).new(0_i64)
      @other_bytes = Atomic(Int64).new(0_i64)
      @degradation_callbacks = {} of MemoryModule => Proc(Int64, Nil)
    end

    # Register degradation callback for a module
    def on_degradation(mod : MemoryModule, &block : Int64 -> Nil)
      @degradation_callbacks[mod] = block
    end

    # Allocate memory for a module (returns false if limit exceeded)
    def allocate(mod : MemoryModule, bytes : Int64) : Bool
      counter = get_counter(mod)
      limit = get_limit(mod)

      loop do
        current = counter.get
        new_value = current + bytes

        if new_value > limit
          # Trigger degradation callback
          trigger_degradation(mod, new_value)
          return false
        end

        if counter.compare_and_set(current, new_value)
          return true
        end
        # CAS failed, retry
      end
    end

    # Try to allocate, with automatic eviction if needed
    def try_allocate(mod : MemoryModule, bytes : Int64, eviction_callback : Proc(Int64, Int64)? = nil) : Bool
      if allocate(mod, bytes)
        return true
      end

      # Try eviction if callback provided
      if callback = eviction_callback
        needed = bytes
        freed = callback.call(needed)
        if freed >= needed
          # Retry allocation after eviction
          return allocate(mod, bytes)
        end
      end

      false
    end

    # Free memory for a module
    def free(mod : MemoryModule, bytes : Int64)
      counter = get_counter(mod)
      counter.sub(bytes)
    end

    # Get current usage for a module
    def usage(mod : MemoryModule) : Int64
      get_counter(mod).get
    end

    # Get limit for a module
    def limit(mod : MemoryModule) : Int64
      get_limit(mod)
    end

    # Get usage percentage for a module
    def usage_percent(mod : MemoryModule) : Float64
      current = usage(mod)
      limit = get_limit(mod)
      return 0.0 if limit == 0
      (current.to_f64 / limit.to_f64) * 100.0
    end

    # Check if module is at or near capacity
    def at_capacity?(mod : MemoryModule, threshold : Float64 = 90.0) : Bool
      usage_percent(mod) >= threshold
    end

    # Get total WAF memory usage
    def total_usage : Int64
      @rate_limiter_bytes.get +
        @challenge_cache_bytes.get +
        @rule_engine_bytes.get +
        @connection_pool_bytes.get +
        @geoip_bytes.get +
        @other_bytes.get
    end

    # Get all module stats
    def stats : NamedTuple(
      rate_limiter: NamedTuple(used: Int64, limit: Int64, percent: Float64),
      challenge_cache: NamedTuple(used: Int64, limit: Int64, percent: Float64),
      rule_engine: NamedTuple(used: Int64, limit: Int64, percent: Float64),
      connection_pool: NamedTuple(used: Int64, limit: Int64, percent: Float64),
      geoip: NamedTuple(used: Int64, limit: Int64, percent: Float64),
      total: NamedTuple(used: Int64, limit: Int64, percent: Float64))
      {
        rate_limiter:    module_stats(MemoryModule::RateLimiter),
        challenge_cache: module_stats(MemoryModule::ChallengeCache),
        rule_engine:     module_stats(MemoryModule::RuleEngine),
        connection_pool: module_stats(MemoryModule::ConnectionPool),
        geoip:           module_stats(MemoryModule::GeoIP),
        total:           {
          used:    total_usage,
          limit:   MemoryLimits::TOTAL_WAF_BYTES,
          percent: (total_usage.to_f64 / MemoryLimits::TOTAL_WAF_BYTES.to_f64) * 100.0,
        },
      }
    end

    # Reset all counters (for testing)
    def reset
      @rate_limiter_bytes.set(0_i64)
      @challenge_cache_bytes.set(0_i64)
      @rule_engine_bytes.set(0_i64)
      @connection_pool_bytes.set(0_i64)
      @geoip_bytes.set(0_i64)
      @other_bytes.set(0_i64)
    end

    private def get_counter(mod : MemoryModule) : Atomic(Int64)
      case mod
      when .rate_limiter?    then @rate_limiter_bytes
      when .challenge_cache? then @challenge_cache_bytes
      when .rule_engine?     then @rule_engine_bytes
      when .connection_pool? then @connection_pool_bytes
      when .geo_ip?          then @geoip_bytes
      else                        @other_bytes
      end
    end

    private def get_limit(mod : MemoryModule) : Int64
      case mod
      when .rate_limiter?    then MemoryLimits::RATE_LIMITER_BYTES
      when .challenge_cache? then MemoryLimits::CHALLENGE_CACHE_BYTES
      when .rule_engine?     then MemoryLimits::RULE_ENGINE_BYTES
      when .connection_pool? then MemoryLimits::CONNECTION_POOL_BYTES
      when .geo_ip?          then MemoryLimits::GEOIP_BYTES
      else                        Int64::MAX
      end
    end

    private def module_stats(mod : MemoryModule) : NamedTuple(used: Int64, limit: Int64, percent: Float64)
      used = usage(mod)
      lim = get_limit(mod)
      {
        used:    used,
        limit:   lim,
        percent: lim > 0 ? (used.to_f64 / lim.to_f64) * 100.0 : 0.0,
      }
    end

    private def trigger_degradation(mod : MemoryModule, current_bytes : Int64)
      Log.warn { "Memory limit exceeded for #{mod}: #{current_bytes} bytes" }
      if callback = @degradation_callbacks[mod]?
        callback.call(current_bytes)
      end
    end
  end

  # =============================================================================
  # Bounded Cache with Memory Tracking
  # =============================================================================
  # Generic cache that respects memory bounds
  # Automatically evicts old entries when limit is reached
  # =============================================================================
  class BoundedCache(K, V)
    Log = ::Log.for("bounded_cache")

    @storage : Hash(K, CacheEntry(V))
    @memory_module : MemoryModule
    @max_entries : Int32
    @entry_size_bytes : Int64
    @mutex : Mutex
    @eviction_order : Array(K) # LRU tracking

    struct CacheEntry(V)
      property value : V
      property created_at : Time
      property last_accessed : Time
      property size_bytes : Int64

      def initialize(@value : V, @size_bytes : Int64)
        @created_at = Time.utc
        @last_accessed = Time.utc
      end

      def touch
        @last_accessed = Time.utc
      end
    end

    def initialize(@memory_module : MemoryModule, @max_entries : Int32 = 10000, @entry_size_bytes : Int64 = 256_i64)
      @storage = {} of K => CacheEntry(V)
      @mutex = Mutex.new
      @eviction_order = [] of K
    end

    # Get value from cache
    def get(key : K) : V?
      @mutex.synchronize do
        if entry = @storage[key]?
          entry.touch
          # Move to end of eviction order (most recently used)
          @eviction_order.delete(key)
          @eviction_order << key
          entry.value
        else
          nil
        end
      end
    end

    # Set value in cache (with memory tracking)
    def set(key : K, value : V, size_bytes : Int64? = nil) : Bool
      actual_size = size_bytes || @entry_size_bytes

      @mutex.synchronize do
        # Check if key already exists
        if existing = @storage[key]?
          # Free old memory
          MemoryTracker.instance.free(@memory_module, existing.size_bytes)
        end

        # Try to allocate memory
        eviction_callback = ->(needed : Int64) {
          evict_lru(needed)
        }

        unless MemoryTracker.instance.try_allocate(@memory_module, actual_size, eviction_callback)
          Log.warn { "Failed to allocate #{actual_size} bytes for cache entry" }
          return false
        end

        # Check max entries
        while @storage.size >= @max_entries && !@eviction_order.empty?
          evict_oldest
        end

        # Store entry
        @storage[key] = CacheEntry(V).new(value, actual_size)
        @eviction_order.delete(key)
        @eviction_order << key

        true
      end
    end

    # Delete value from cache
    def delete(key : K) : Bool
      @mutex.synchronize do
        if entry = @storage.delete(key)
          MemoryTracker.instance.free(@memory_module, entry.size_bytes)
          @eviction_order.delete(key)
          true
        else
          false
        end
      end
    end

    # Check if key exists
    def has_key?(key : K) : Bool
      @mutex.synchronize { @storage.has_key?(key) }
    end

    # Get cache size
    def size : Int32
      @mutex.synchronize { @storage.size }
    end

    # Clear all entries
    def clear
      @mutex.synchronize do
        @storage.each do |_, entry|
          MemoryTracker.instance.free(@memory_module, entry.size_bytes)
        end
        @storage.clear
        @eviction_order.clear
      end
    end

    # Get cache statistics
    def stats : NamedTuple(entries: Int32, max_entries: Int32, memory_module: MemoryModule)
      @mutex.synchronize do
        {
          entries:       @storage.size,
          max_entries:   @max_entries,
          memory_module: @memory_module,
        }
      end
    end

    private def evict_oldest
      if oldest_key = @eviction_order.shift?
        if entry = @storage.delete(oldest_key)
          MemoryTracker.instance.free(@memory_module, entry.size_bytes)
          Log.debug { "Evicted oldest cache entry" }
        end
      end
    end

    private def evict_lru(needed_bytes : Int64) : Int64
      freed = 0_i64

      while freed < needed_bytes && !@eviction_order.empty?
        if oldest_key = @eviction_order.shift?
          if entry = @storage.delete(oldest_key)
            MemoryTracker.instance.free(@memory_module, entry.size_bytes)
            freed += entry.size_bytes
          end
        end
      end

      Log.debug { "Evicted #{freed} bytes to make room for #{needed_bytes}" } if freed > 0
      freed
    end
  end

  # =============================================================================
  # Memory-Bounded Map
  # =============================================================================
  # Hash map with memory limits - used for rate limiter state, etc.
  # =============================================================================
  class BoundedMap(K, V)
    Log = ::Log.for("bounded_map")

    @storage : Hash(K, V)
    @memory_module : MemoryModule
    @entry_size_bytes : Int64
    @mutex : Mutex

    def initialize(@memory_module : MemoryModule, @entry_size_bytes : Int64 = 128_i64)
      @storage = {} of K => V
      @mutex = Mutex.new
    end

    # Get value
    def get(key : K) : V?
      @mutex.synchronize { @storage[key]? }
    end

    # Set value (returns false if memory limit reached)
    def set(key : K, value : V) : Bool
      @mutex.synchronize do
        is_new = !@storage.has_key?(key)

        if is_new
          unless MemoryTracker.instance.allocate(@memory_module, @entry_size_bytes)
            Log.warn { "Memory limit reached, cannot add new entry" }
            return false
          end
        end

        @storage[key] = value
        true
      end
    end

    # Delete value
    def delete(key : K) : V?
      @mutex.synchronize do
        if value = @storage.delete(key)
          MemoryTracker.instance.free(@memory_module, @entry_size_bytes)
          value
        else
          nil
        end
      end
    end

    # Get or create with factory
    def get_or_create(key : K, &block : -> V) : V?
      @mutex.synchronize do
        if existing = @storage[key]?
          return existing
        end

        unless MemoryTracker.instance.allocate(@memory_module, @entry_size_bytes)
          return nil
        end

        value = yield
        @storage[key] = value
        value
      end
    end

    # Size
    def size : Int32
      @mutex.synchronize { @storage.size }
    end

    # Clear all
    def clear
      @mutex.synchronize do
        count = @storage.size
        @storage.clear
        MemoryTracker.instance.free(@memory_module, count.to_i64 * @entry_size_bytes)
      end
    end

    # Iterate (with lock)
    def each(&block : K, V ->)
      @mutex.synchronize do
        @storage.each { |k, v| yield k, v }
      end
    end
  end
end
