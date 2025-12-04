require "atomic"

module KemalWAF
  # =============================================================================
  # PROMETHEUS METRICS IMPLEMENTATION
  # =============================================================================
  # 25 fixed metrics for observability:
  # - Request metrics (5)
  # - Backend metrics (4)
  # - Rate limit metrics (3)
  # - Connection pool metrics (4)
  # - Memory metrics (3)
  # - Rule engine metrics (3)
  # - System metrics (3)
  # =============================================================================

  # Metrics buffer for batch updates
  METRICS_BUFFER_SIZE    = 100
  METRICS_FLUSH_INTERVAL = 500 # milliseconds

  # =============================================================================
  # Histogram Bucket Helper
  # =============================================================================
  # Simple histogram implementation with fixed buckets
  # =============================================================================
  class HistogramBuckets
    @buckets : Array(Float64)
    @counts : Array(Atomic(Int64))
    @sum : Atomic(Int64)     # Sum in microseconds
    @count : Atomic(Int64)   # Total count

    def initialize(@buckets : Array(Float64) = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0])
      @counts = @buckets.map { Atomic(Int64).new(0_i64) }
      @counts << Atomic(Int64).new(0_i64) # +Inf bucket
      @sum = Atomic(Int64).new(0_i64)
      @count = Atomic(Int64).new(0_i64)
    end

    # Observe a value (in seconds)
    def observe(value : Float64)
      @count.add(1_i64)
      @sum.add((value * 1_000_000).to_i64) # Convert to microseconds

      # Find bucket
      @buckets.each_with_index do |bucket, idx|
        if value <= bucket
          @counts[idx].add(1_i64)
        end
      end
      # +Inf bucket always gets incremented
      @counts.last.add(1_i64)
    end

    # Get bucket counts
    def bucket_counts : Array(Tuple(Float64, Int64))
      result = [] of Tuple(Float64, Int64)
      @buckets.each_with_index do |bucket, idx|
        result << {bucket, @counts[idx].get}
      end
      result << {Float64::INFINITY, @counts.last.get}
      result
    end

    def sum : Float64
      @sum.get.to_f64 / 1_000_000.0 # Convert back to seconds
    end

    def count : Int64
      @count.get
    end

    def reset
      @counts.each(&.set(0_i64))
      @sum.set(0_i64)
      @count.set(0_i64)
    end
  end

  # =============================================================================
  # Prometheus Metrics Manager
  # =============================================================================
  class Metrics
    Log = ::Log.for("metrics")

    # =========================================================================
    # Request Metrics (5)
    # =========================================================================
    @requests_total : Atomic(Int64)
    @blocked_total : Atomic(Int64)
    @observed_total : Atomic(Int64)
    @request_duration : HistogramBuckets
    @request_size_bytes : Atomic(Int64)

    # =========================================================================
    # Backend Metrics (4)
    # =========================================================================
    @backend_requests_total : Atomic(Int64)
    @backend_errors_total : Atomic(Int64)
    @backend_retries_total : Atomic(Int64)
    @backend_latency : HistogramBuckets

    # =========================================================================
    # Rate Limit Metrics (3)
    # =========================================================================
    @rate_limited_total : Atomic(Int64)
    @rate_limit_active_counters : Atomic(Int32)
    @blocked_ips_total : Atomic(Int32)

    # =========================================================================
    # Connection Pool Metrics (4)
    # =========================================================================
    @pool_size : Atomic(Int32)
    @pool_available : Atomic(Int32)
    @pool_acquired : Atomic(Int64)
    @pool_timeouts : Atomic(Int64)

    # =========================================================================
    # Memory Metrics (3)
    # =========================================================================
    @memory_usage_bytes : Atomic(Int64)
    @gc_runs_total : Atomic(Int64)
    @gc_duration : HistogramBuckets

    # =========================================================================
    # Rule Engine Metrics (3)
    # =========================================================================
    @rules_loaded : Atomic(Int32)
    @rule_evaluation_duration : HistogramBuckets
    @snapshot_version : Atomic(Int64)

    # =========================================================================
    # System Metrics (3)
    # =========================================================================
    @uptime_seconds : Atomic(Int64)
    @fiber_crashes_total : Atomic(Int64)
    @config_reloads_total : Atomic(Int64)

    # Start time for uptime calculation
    @start_time : Time

    def initialize
      # Request metrics
      @requests_total = Atomic(Int64).new(0_i64)
      @blocked_total = Atomic(Int64).new(0_i64)
      @observed_total = Atomic(Int64).new(0_i64)
      @request_duration = HistogramBuckets.new([0.0001, 0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0])
      @request_size_bytes = Atomic(Int64).new(0_i64)

      # Backend metrics
      @backend_requests_total = Atomic(Int64).new(0_i64)
      @backend_errors_total = Atomic(Int64).new(0_i64)
      @backend_retries_total = Atomic(Int64).new(0_i64)
      @backend_latency = HistogramBuckets.new([0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0])

      # Rate limit metrics
      @rate_limited_total = Atomic(Int64).new(0_i64)
      @rate_limit_active_counters = Atomic(Int32).new(0)
      @blocked_ips_total = Atomic(Int32).new(0)

      # Connection pool metrics
      @pool_size = Atomic(Int32).new(0)
      @pool_available = Atomic(Int32).new(0)
      @pool_acquired = Atomic(Int64).new(0_i64)
      @pool_timeouts = Atomic(Int64).new(0_i64)

      # Memory metrics
      @memory_usage_bytes = Atomic(Int64).new(0_i64)
      @gc_runs_total = Atomic(Int64).new(0_i64)
      @gc_duration = HistogramBuckets.new([0.0001, 0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1])

      # Rule engine metrics
      @rules_loaded = Atomic(Int32).new(0)
      @rule_evaluation_duration = HistogramBuckets.new([0.00001, 0.00005, 0.0001, 0.0005, 0.001, 0.005, 0.01])
      @snapshot_version = Atomic(Int64).new(0_i64)

      # System metrics
      @uptime_seconds = Atomic(Int64).new(0_i64)
      @fiber_crashes_total = Atomic(Int64).new(0_i64)
      @config_reloads_total = Atomic(Int64).new(0_i64)

      @start_time = Time.utc

      # Start uptime updater
      spawn update_uptime_loop
    end

    # =========================================================================
    # Request Metric Methods
    # =========================================================================

    def increment_requests
      @requests_total.add(1_i64)
    end

    def increment_blocked
      @blocked_total.add(1_i64)
    end

    def increment_observed
      @observed_total.add(1_i64)
    end

    def observe_request_duration(duration_seconds : Float64)
      @request_duration.observe(duration_seconds)
    end

    def add_request_size(size_bytes : Int64)
      @request_size_bytes.add(size_bytes)
    end

    # =========================================================================
    # Backend Metric Methods
    # =========================================================================

    def increment_backend_requests
      @backend_requests_total.add(1_i64)
    end

    def increment_backend_errors
      @backend_errors_total.add(1_i64)
    end

    def increment_backend_retries
      @backend_retries_total.add(1_i64)
    end

    def observe_backend_latency(duration_seconds : Float64)
      @backend_latency.observe(duration_seconds)
    end

    # =========================================================================
    # Rate Limit Metric Methods
    # =========================================================================

    def increment_rate_limited
      @rate_limited_total.add(1_i64)
    end

    def set_rate_limit_counters(count : Int32)
      @rate_limit_active_counters.set(count)
    end

    def set_blocked_ips(count : Int32)
      @blocked_ips_total.set(count)
    end

    # =========================================================================
    # Connection Pool Metric Methods
    # =========================================================================

    def set_pool_size(size : Int32)
      @pool_size.set(size)
    end

    def set_pool_available(available : Int32)
      @pool_available.set(available)
    end

    def increment_pool_acquired
      @pool_acquired.add(1_i64)
    end

    def increment_pool_timeouts
      @pool_timeouts.add(1_i64)
    end

    # =========================================================================
    # Memory Metric Methods
    # =========================================================================

    def set_memory_usage(bytes : Int64)
      @memory_usage_bytes.set(bytes)
    end

    def increment_gc_runs
      @gc_runs_total.add(1_i64)
    end

    def observe_gc_duration(duration_seconds : Float64)
      @gc_duration.observe(duration_seconds)
    end

    # =========================================================================
    # Rule Engine Metric Methods
    # =========================================================================

    def set_rules_loaded(count : Int32)
      @rules_loaded.set(count)
    end

    def observe_rule_evaluation(duration_seconds : Float64)
      @rule_evaluation_duration.observe(duration_seconds)
    end

    def set_snapshot_version(version : Int64)
      @snapshot_version.set(version)
    end

    # =========================================================================
    # System Metric Methods
    # =========================================================================

    def increment_fiber_crashes
      @fiber_crashes_total.add(1_i64)
    end

    def increment_config_reloads
      @config_reloads_total.add(1_i64)
    end

    # =========================================================================
    # Prometheus Output
    # =========================================================================

    def to_prometheus : String
      String.build do |str|
        # =======================================================================
        # Request Metrics (5)
        # =======================================================================
        str << "# HELP waf_requests_total Total number of requests processed\n"
        str << "# TYPE waf_requests_total counter\n"
        str << "waf_requests_total #{@requests_total.get}\n\n"

        str << "# HELP waf_blocked_total Total number of blocked requests\n"
        str << "# TYPE waf_blocked_total counter\n"
        str << "waf_blocked_total #{@blocked_total.get}\n\n"

        str << "# HELP waf_observed_total Total number of observed (not blocked) rule matches\n"
        str << "# TYPE waf_observed_total counter\n"
        str << "waf_observed_total #{@observed_total.get}\n\n"

        str << "# HELP waf_request_duration_seconds Request duration histogram\n"
        str << "# TYPE waf_request_duration_seconds histogram\n"
        @request_duration.bucket_counts.each do |bucket, count|
          le = bucket.infinite? ? "+Inf" : bucket.to_s
          str << "waf_request_duration_seconds_bucket{le=\"#{le}\"} #{count}\n"
        end
        str << "waf_request_duration_seconds_sum #{@request_duration.sum}\n"
        str << "waf_request_duration_seconds_count #{@request_duration.count}\n\n"

        str << "# HELP waf_request_size_bytes_total Total request size in bytes\n"
        str << "# TYPE waf_request_size_bytes_total counter\n"
        str << "waf_request_size_bytes_total #{@request_size_bytes.get}\n\n"

        # =======================================================================
        # Backend Metrics (4)
        # =======================================================================
        str << "# HELP waf_backend_requests_total Total backend requests\n"
        str << "# TYPE waf_backend_requests_total counter\n"
        str << "waf_backend_requests_total #{@backend_requests_total.get}\n\n"

        str << "# HELP waf_backend_errors_total Total backend errors\n"
        str << "# TYPE waf_backend_errors_total counter\n"
        str << "waf_backend_errors_total #{@backend_errors_total.get}\n\n"

        str << "# HELP waf_backend_retries_total Total backend retries\n"
        str << "# TYPE waf_backend_retries_total counter\n"
        str << "waf_backend_retries_total #{@backend_retries_total.get}\n\n"

        str << "# HELP waf_backend_latency_seconds Backend latency histogram\n"
        str << "# TYPE waf_backend_latency_seconds histogram\n"
        @backend_latency.bucket_counts.each do |bucket, count|
          le = bucket.infinite? ? "+Inf" : bucket.to_s
          str << "waf_backend_latency_seconds_bucket{le=\"#{le}\"} #{count}\n"
        end
        str << "waf_backend_latency_seconds_sum #{@backend_latency.sum}\n"
        str << "waf_backend_latency_seconds_count #{@backend_latency.count}\n\n"

        # =======================================================================
        # Rate Limit Metrics (3)
        # =======================================================================
        str << "# HELP waf_rate_limited_total Total rate limited requests\n"
        str << "# TYPE waf_rate_limited_total counter\n"
        str << "waf_rate_limited_total #{@rate_limited_total.get}\n\n"

        str << "# HELP waf_rate_limit_active_counters Number of active rate limit counters\n"
        str << "# TYPE waf_rate_limit_active_counters gauge\n"
        str << "waf_rate_limit_active_counters #{@rate_limit_active_counters.get}\n\n"

        str << "# HELP waf_blocked_ips_total Number of currently blocked IPs\n"
        str << "# TYPE waf_blocked_ips_total gauge\n"
        str << "waf_blocked_ips_total #{@blocked_ips_total.get}\n\n"

        # =======================================================================
        # Connection Pool Metrics (4)
        # =======================================================================
        str << "# HELP waf_pool_size Connection pool size\n"
        str << "# TYPE waf_pool_size gauge\n"
        str << "waf_pool_size #{@pool_size.get}\n\n"

        str << "# HELP waf_pool_available Available connections in pool\n"
        str << "# TYPE waf_pool_available gauge\n"
        str << "waf_pool_available #{@pool_available.get}\n\n"

        str << "# HELP waf_pool_acquired_total Total pool connections acquired\n"
        str << "# TYPE waf_pool_acquired_total counter\n"
        str << "waf_pool_acquired_total #{@pool_acquired.get}\n\n"

        str << "# HELP waf_pool_timeouts_total Total pool acquisition timeouts\n"
        str << "# TYPE waf_pool_timeouts_total counter\n"
        str << "waf_pool_timeouts_total #{@pool_timeouts.get}\n\n"

        # =======================================================================
        # Memory Metrics (3)
        # =======================================================================
        str << "# HELP waf_memory_usage_bytes Current memory usage in bytes\n"
        str << "# TYPE waf_memory_usage_bytes gauge\n"
        str << "waf_memory_usage_bytes #{@memory_usage_bytes.get}\n\n"

        str << "# HELP waf_gc_runs_total Total garbage collection runs\n"
        str << "# TYPE waf_gc_runs_total counter\n"
        str << "waf_gc_runs_total #{@gc_runs_total.get}\n\n"

        str << "# HELP waf_gc_duration_seconds GC duration histogram\n"
        str << "# TYPE waf_gc_duration_seconds histogram\n"
        @gc_duration.bucket_counts.each do |bucket, count|
          le = bucket.infinite? ? "+Inf" : bucket.to_s
          str << "waf_gc_duration_seconds_bucket{le=\"#{le}\"} #{count}\n"
        end
        str << "waf_gc_duration_seconds_sum #{@gc_duration.sum}\n"
        str << "waf_gc_duration_seconds_count #{@gc_duration.count}\n\n"

        # =======================================================================
        # Rule Engine Metrics (3)
        # =======================================================================
        str << "# HELP waf_rules_loaded Number of currently loaded rules\n"
        str << "# TYPE waf_rules_loaded gauge\n"
        str << "waf_rules_loaded #{@rules_loaded.get}\n\n"

        str << "# HELP waf_rule_evaluation_seconds Rule evaluation duration histogram\n"
        str << "# TYPE waf_rule_evaluation_seconds histogram\n"
        @rule_evaluation_duration.bucket_counts.each do |bucket, count|
          le = bucket.infinite? ? "+Inf" : bucket.to_s
          str << "waf_rule_evaluation_seconds_bucket{le=\"#{le}\"} #{count}\n"
        end
        str << "waf_rule_evaluation_seconds_sum #{@rule_evaluation_duration.sum}\n"
        str << "waf_rule_evaluation_seconds_count #{@rule_evaluation_duration.count}\n\n"

        str << "# HELP waf_snapshot_version Current rule snapshot version\n"
        str << "# TYPE waf_snapshot_version gauge\n"
        str << "waf_snapshot_version #{@snapshot_version.get}\n\n"

        # =======================================================================
        # System Metrics (3)
        # =======================================================================
        str << "# HELP waf_uptime_seconds WAF uptime in seconds\n"
        str << "# TYPE waf_uptime_seconds gauge\n"
        str << "waf_uptime_seconds #{@uptime_seconds.get}\n\n"

        str << "# HELP waf_fiber_crashes_total Total fiber crashes\n"
        str << "# TYPE waf_fiber_crashes_total counter\n"
        str << "waf_fiber_crashes_total #{@fiber_crashes_total.get}\n\n"

        str << "# HELP waf_config_reloads_total Total configuration reloads\n"
        str << "# TYPE waf_config_reloads_total counter\n"
        str << "waf_config_reloads_total #{@config_reloads_total.get}\n"
      end
    end

    private def update_uptime_loop
      loop do
        sleep 1.second
        @uptime_seconds.set((Time.utc - @start_time).total_seconds.to_i64)
      end
    end
  end
end
