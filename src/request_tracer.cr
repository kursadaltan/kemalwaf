require "uuid"
require "atomic"

module KemalWAF
  # =============================================================================
  # REQUEST TRACING IMPLEMENTATION
  # =============================================================================
  # Granular latency breakdown for each request:
  # - DNS latency
  # - Load balancer latency
  # - Edge/WAF latency
  # - Backend latency
  # - Response write latency
  # - GC time (target: 0)
  # =============================================================================

  # Trace point indices for array-based storage
  enum TracePoint
    Start           = 0  # Request received
    DnsComplete     = 1  # DNS resolution complete
    LbComplete      = 2  # Load balancer routing complete
    WafStart        = 3  # WAF evaluation start
    WafComplete     = 4  # WAF evaluation complete
    BackendStart    = 5  # Backend request start
    BackendComplete = 6  # Backend response received
    ResponseStart   = 7  # Response writing start
    ResponseComplete = 8 # Response writing complete
    GcStart         = 9  # GC started (if any)
    GcComplete      = 10 # GC completed
    End             = 11 # Request complete
  end

  TRACE_POINTS_COUNT = 12

  # =============================================================================
  # Request Trace
  # =============================================================================
  # Holds timing information for a single request
  # Uses nanosecond precision timestamps
  # =============================================================================
  class RequestTrace
    @request_id : String
    @timestamps : StaticArray(Int64, TRACE_POINTS_COUNT)
    @recorded : StaticArray(Bool, TRACE_POINTS_COUNT)
    @metadata : Hash(String, String)
    @created_at : Time

    getter request_id : String
    getter created_at : Time

    def initialize(@request_id : String = UUID.random.to_s)
      @timestamps = StaticArray(Int64, TRACE_POINTS_COUNT).new(0_i64)
      @recorded = StaticArray(Bool, TRACE_POINTS_COUNT).new(false)
      @metadata = {} of String => String
      @created_at = Time.utc
      
      # Record start time immediately
      record(TracePoint::Start)
    end

    # Record a trace point
    def record(point : TracePoint)
      idx = point.value
      @timestamps[idx] = Time.monotonic.total_nanoseconds.to_i64
      @recorded[idx] = true
    end

    # Record with custom timestamp
    def record(point : TracePoint, timestamp_ns : Int64)
      idx = point.value
      @timestamps[idx] = timestamp_ns
      @recorded[idx] = true
    end

    # Get timestamp for a trace point (returns nil if not recorded)
    def timestamp(point : TracePoint) : Int64?
      idx = point.value
      @recorded[idx] ? @timestamps[idx] : nil
    end

    # Calculate duration between two points (in nanoseconds)
    def duration_ns(from : TracePoint, to : TracePoint) : Int64?
      from_ts = timestamp(from)
      to_ts = timestamp(to)
      return nil unless from_ts && to_ts
      to_ts - from_ts
    end

    # Calculate duration in microseconds
    def duration_us(from : TracePoint, to : TracePoint) : Float64?
      ns = duration_ns(from, to)
      ns ? ns.to_f64 / 1000.0 : nil
    end

    # Calculate duration in milliseconds
    def duration_ms(from : TracePoint, to : TracePoint) : Float64?
      ns = duration_ns(from, to)
      ns ? ns.to_f64 / 1_000_000.0 : nil
    end

    # Add metadata
    def add_metadata(key : String, value : String)
      @metadata[key] = value
    end

    # Get metadata
    def metadata(key : String) : String?
      @metadata[key]?
    end

    # =============================================================================
    # Latency Breakdown
    # =============================================================================

    # Total request duration
    def total_duration_ns : Int64?
      duration_ns(TracePoint::Start, TracePoint::End) ||
        duration_ns(TracePoint::Start, TracePoint::ResponseComplete)
    end

    def total_duration_ms : Float64?
      ns = total_duration_ns
      ns ? ns.to_f64 / 1_000_000.0 : nil
    end

    # WAF evaluation duration
    def waf_duration_ns : Int64?
      duration_ns(TracePoint::WafStart, TracePoint::WafComplete)
    end

    def waf_duration_us : Float64?
      ns = waf_duration_ns
      ns ? ns.to_f64 / 1000.0 : nil
    end

    # Backend latency
    def backend_duration_ns : Int64?
      duration_ns(TracePoint::BackendStart, TracePoint::BackendComplete)
    end

    def backend_duration_ms : Float64?
      ns = backend_duration_ns
      ns ? ns.to_f64 / 1_000_000.0 : nil
    end

    # Response write duration
    def response_duration_ns : Int64?
      duration_ns(TracePoint::ResponseStart, TracePoint::ResponseComplete)
    end

    def response_duration_us : Float64?
      ns = response_duration_ns
      ns ? ns.to_f64 / 1000.0 : nil
    end

    # GC duration (should be 0 in ideal case)
    def gc_duration_ns : Int64?
      duration_ns(TracePoint::GcStart, TracePoint::GcComplete)
    end

    # =============================================================================
    # Serialization
    # =============================================================================

    def to_json_object : Hash(String, String | Float64 | Int64 | Nil)
      {
        "request_id"          => @request_id,
        "created_at"          => @created_at.to_rfc3339,
        "total_duration_ms"   => total_duration_ms,
        "waf_duration_us"     => waf_duration_us,
        "backend_duration_ms" => backend_duration_ms,
        "response_duration_us" => response_duration_us,
        "gc_duration_ns"      => gc_duration_ns,
      }
    end

    def to_json : String
      parts = [] of String
      parts << %("request_id":"#{@request_id}")
      parts << %("created_at":"#{@created_at.to_rfc3339}")
      
      if total_ms = total_duration_ms
        parts << %("total_duration_ms":#{total_ms.round(3)})
      end
      
      if waf_us = waf_duration_us
        parts << %("waf_duration_us":#{waf_us.round(3)})
      end
      
      if backend_ms = backend_duration_ms
        parts << %("backend_duration_ms":#{backend_ms.round(3)})
      end
      
      if response_us = response_duration_us
        parts << %("response_duration_us":#{response_us.round(3)})
      end
      
      if gc_ns = gc_duration_ns
        parts << %("gc_duration_ns":#{gc_ns})
      end

      @metadata.each do |key, value|
        parts << %("#{key}":"#{value}")
      end

      "{#{parts.join(",")}}"
    end

    # Format for logging
    def to_log_string : String
      parts = ["req_id=#{@request_id}"]
      
      if total_ms = total_duration_ms
        parts << "total=#{total_ms.round(2)}ms"
      end
      
      if waf_us = waf_duration_us
        parts << "waf=#{waf_us.round(2)}µs"
      end
      
      if backend_ms = backend_duration_ms
        parts << "backend=#{backend_ms.round(2)}ms"
      end
      
      if gc_ns = gc_duration_ns
        parts << "gc=#{gc_ns}ns"
      end

      parts.join(" | ")
    end
  end

  # =============================================================================
  # Request Trace Pool
  # =============================================================================
  # Preallocated pool of RequestTrace objects for zero-allocation in hotpath
  # =============================================================================
  class RequestTracePool
    Log = ::Log.for("trace_pool")

    POOL_SIZE = 512

    @pool : Channel(RequestTrace)
    @created : Atomic(Int32)

    def initialize
      @pool = Channel(RequestTrace).new(POOL_SIZE)
      @created = Atomic(Int32).new(0)

      # Pre-fill pool
      POOL_SIZE.times do
        @pool.send(RequestTrace.new)
        @created.add(1)
      end

      Log.info { "RequestTracePool initialized with #{POOL_SIZE} traces" }
    end

    def acquire(request_id : String? = nil) : RequestTrace
      select
      when trace = @pool.receive
        # Reset trace for reuse
        trace = RequestTrace.new(request_id || UUID.random.to_s)
        trace
      else
        @created.add(1)
        RequestTrace.new(request_id || UUID.random.to_s)
      end
    end

    def release(trace : RequestTrace)
      select
      when @pool.send(trace)
      else
        # Pool full, let GC collect it
      end
    end

    def stats : NamedTuple(pool_size: Int32, created: Int32)
      {pool_size: POOL_SIZE, created: @created.get}
    end
  end

  # =============================================================================
  # Global Request Tracer
  # =============================================================================
  # Singleton tracer for managing request traces
  # =============================================================================
  class RequestTracer
    Log = ::Log.for("request_tracer")

    @@instance : RequestTracer?
    @pool : RequestTracePool
    @enabled : Bool
    @sample_rate : Float64 # 0.0 to 1.0

    # Statistics
    @traces_created : Atomic(Int64)
    @traces_completed : Atomic(Int64)

    def self.instance : RequestTracer
      @@instance ||= new
    end

    private def initialize
      @pool = RequestTracePool.new
      @enabled = true
      @sample_rate = 1.0 # 100% by default
      @traces_created = Atomic(Int64).new(0_i64)
      @traces_completed = Atomic(Int64).new(0_i64)
    end

    # Enable/disable tracing
    def enabled=(value : Bool)
      @enabled = value
    end

    def enabled? : Bool
      @enabled
    end

    # Set sample rate (0.0 to 1.0)
    def sample_rate=(rate : Float64)
      @sample_rate = rate.clamp(0.0, 1.0)
    end

    def sample_rate : Float64
      @sample_rate
    end

    # Start a new trace
    def start_trace(request_id : String? = nil) : RequestTrace?
      return nil unless @enabled
      return nil unless should_sample?

      trace = @pool.acquire(request_id)
      @traces_created.add(1_i64)
      trace
    end

    # Complete a trace
    def complete_trace(trace : RequestTrace?)
      return unless trace
      trace.record(TracePoint::End)
      @traces_completed.add(1_i64)
      
      # Log trace if debug enabled
      Log.debug { trace.to_log_string }
      
      @pool.release(trace)
    end

    # Should we sample this request?
    private def should_sample? : Bool
      return true if @sample_rate >= 1.0
      return false if @sample_rate <= 0.0
      Random.rand < @sample_rate
    end

    # Get statistics
    def stats : NamedTuple(enabled: Bool, sample_rate: Float64, created: Int64, completed: Int64)
      {
        enabled: @enabled,
        sample_rate: @sample_rate,
        created: @traces_created.get,
        completed: @traces_completed.get
      }
    end
  end

  # =============================================================================
  # Trace Context Helper
  # =============================================================================
  # Helper module for easy tracing integration
  # =============================================================================
  module TraceContext
    def self.start(request_id : String? = nil) : RequestTrace?
      RequestTracer.instance.start_trace(request_id)
    end

    def self.record(trace : RequestTrace?, point : TracePoint)
      trace.try(&.record(point))
    end

    def self.complete(trace : RequestTrace?)
      RequestTracer.instance.complete_trace(trace)
    end

    def self.with_trace(request_id : String? = nil, &block : RequestTrace? -> )
      trace = start(request_id)
      begin
        yield trace
      ensure
        complete(trace)
      end
    end
  end
end

