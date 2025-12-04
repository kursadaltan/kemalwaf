require "atomic"

module KemalWAF
  # =============================================================================
  # PANIC ISOLATION IMPLEMENTATION
  # =============================================================================
  # Fiber crash recovery and isolation:
  # - Isolated fiber execution
  # - Automatic restart on crash
  # - Error logging and reporting
  # - Crash statistics
  # =============================================================================

  # Fiber state
  enum FiberState
    Running
    Crashed
    Restarting
    Stopped
  end

  # =============================================================================
  # Isolated Fiber Info
  # =============================================================================
  # Tracks state and statistics for an isolated fiber
  # =============================================================================
  class IsolatedFiberInfo
    property name : String
    property state : FiberState
    property crash_count : Int32
    property last_crash : Time?
    property last_error : String?
    property started_at : Time
    property restart_delay_ms : Int32

    def initialize(@name : String, @restart_delay_ms : Int32 = 1000)
      @state = FiberState::Running
      @crash_count = 0
      @last_crash = nil
      @last_error = nil
      @started_at = Time.utc
    end

    def record_crash(error : String)
      @crash_count += 1
      @last_crash = Time.utc
      @last_error = error
      @state = FiberState::Crashed
    end

    def mark_restarting
      @state = FiberState::Restarting
    end

    def mark_running
      @state = FiberState::Running
      @started_at = Time.utc
    end

    def mark_stopped
      @state = FiberState::Stopped
    end

    def uptime : Time::Span
      Time.utc - @started_at
    end
  end

  # =============================================================================
  # Panic Isolator
  # =============================================================================
  # Manages isolated fiber execution with crash recovery
  # =============================================================================
  class PanicIsolator
    Log = ::Log.for("panic_isolator")

    @@instance : PanicIsolator?

    @fibers : Hash(String, IsolatedFiberInfo)
    @mutex : Mutex
    @enabled : Bool
    @max_restarts : Int32
    @restart_delay_ms : Int32
    @crash_callback : Proc(String, Exception, Nil)?

    # Statistics
    @total_crashes : Atomic(Int64)
    @total_restarts : Atomic(Int64)

    def self.instance : PanicIsolator
      @@instance ||= new
    end

    private def initialize
      @fibers = {} of String => IsolatedFiberInfo
      @mutex = Mutex.new
      @enabled = true
      @max_restarts = 10
      @restart_delay_ms = 1000
      @crash_callback = nil
      @total_crashes = Atomic(Int64).new(0_i64)
      @total_restarts = Atomic(Int64).new(0_i64)
    end

    # Configure isolator
    def configure(max_restarts : Int32? = nil, restart_delay_ms : Int32? = nil)
      @max_restarts = max_restarts if max_restarts
      @restart_delay_ms = restart_delay_ms if restart_delay_ms
    end

    # Set crash callback
    def on_crash(&block : String, Exception -> Nil)
      @crash_callback = block
    end

    # Enable/disable isolation
    def enabled=(value : Bool)
      @enabled = value
    end

    def enabled? : Bool
      @enabled
    end

    # =============================================================================
    # Spawn Isolated Fiber
    # =============================================================================
    # Creates a fiber with automatic crash recovery
    # If the fiber crashes, it will be automatically restarted
    # =============================================================================
    def spawn_isolated(name : String, restart_delay_ms : Int32? = nil, &block : ->)
      delay = restart_delay_ms || @restart_delay_ms

      # Register fiber
      fiber_info = @mutex.synchronize do
        new_info = IsolatedFiberInfo.new(name, delay)
        @fibers[name] = new_info
        new_info
      end

      Log.info { "Starting isolated fiber: #{name}" }
      spawn_fiber_with_recovery(name, fiber_info, block)
    end

    # =============================================================================
    # Spawn with Retry
    # =============================================================================
    # Spawns a fiber that will retry on failure with backoff
    # =============================================================================
    def spawn_with_retry(name : String, max_retries : Int32 = 3, base_delay_ms : Int32 = 100, &block : ->)
      fiber_info = @mutex.synchronize do
        new_info = IsolatedFiberInfo.new(name, base_delay_ms)
        @fibers[name] = new_info
        new_info
      end

      spawn do
        retries = 0
        while retries < max_retries
          begin
            fiber_info.mark_running
            block.call
            break # Success, exit loop
          rescue ex
            retries += 1
            fiber_info.record_crash(ex.message || "Unknown error")
            @total_crashes.add(1_i64)

            Log.error { "Fiber #{name} crashed (attempt #{retries}/#{max_retries}): #{ex.message}" }
            Log.debug { ex.backtrace.join("\n") if ex.backtrace }

            @crash_callback.try(&.call(name, ex))

            if retries < max_retries
              delay = base_delay_ms * (2 ** (retries - 1)) # Exponential backoff
              Log.info { "Retrying fiber #{name} in #{delay}ms..." }
              sleep delay.milliseconds
              @total_restarts.add(1_i64)
            else
              Log.error { "Fiber #{name} failed after #{max_retries} attempts, giving up" }
              fiber_info.mark_stopped
            end
          end
        end
      end
    end

    # =============================================================================
    # Stop Fiber
    # =============================================================================
    def stop_fiber(name : String)
      @mutex.synchronize do
        if info = @fibers[name]?
          info.mark_stopped
          Log.info { "Fiber #{name} marked as stopped" }
        end
      end
    end

    # =============================================================================
    # Get Fiber Info
    # =============================================================================
    def fiber_info(name : String) : IsolatedFiberInfo?
      @mutex.synchronize { @fibers[name]? }
    end

    # =============================================================================
    # Get All Fibers Status
    # =============================================================================
    def all_fibers : Array(NamedTuple(name: String, state: FiberState, crash_count: Int32, uptime_seconds: Int64))
      @mutex.synchronize do
        @fibers.map do |name, info|
          {
            name:           name,
            state:          info.state,
            crash_count:    info.crash_count,
            uptime_seconds: info.uptime.total_seconds.to_i64,
          }
        end
      end
    end

    # =============================================================================
    # Statistics
    # =============================================================================
    def stats : NamedTuple(
      enabled: Bool,
      total_fibers: Int32,
      running_fibers: Int32,
      crashed_fibers: Int32,
      stopped_fibers: Int32,
      total_crashes: Int64,
      total_restarts: Int64)
      @mutex.synchronize do
        running = @fibers.count { |_, info| info.state.running? }
        crashed = @fibers.count { |_, info| info.state.crashed? }
        stopped = @fibers.count { |_, info| info.state.stopped? }

        {
          enabled:        @enabled,
          total_fibers:   @fibers.size,
          running_fibers: running,
          crashed_fibers: crashed,
          stopped_fibers: stopped,
          total_crashes:  @total_crashes.get,
          total_restarts: @total_restarts.get,
        }
      end
    end

    # =============================================================================
    # Internal: Spawn Fiber with Recovery
    # =============================================================================
    private def spawn_fiber_with_recovery(name : String, info : IsolatedFiberInfo, block : Proc(Nil))
      spawn do
        loop do
          break if info.state.stopped?
          break unless @enabled

          begin
            info.mark_running
            block.call
            # If block returns normally, fiber is done
            Log.info { "Fiber #{name} completed normally" }
            break
          rescue ex
            @total_crashes.add(1_i64)
            info.record_crash(ex.message || "Unknown error")

            Log.error { "Fiber #{name} crashed: #{ex.message}" }
            Log.debug { ex.backtrace.join("\n") if ex.backtrace }

            # Call crash callback
            @crash_callback.try(&.call(name, ex))

            # Check restart limit
            if info.crash_count >= @max_restarts
              Log.error { "Fiber #{name} exceeded max restarts (#{@max_restarts}), stopping" }
              info.mark_stopped
              break
            end

            # Restart after delay
            info.mark_restarting
            Log.info { "Restarting fiber #{name} in #{info.restart_delay_ms}ms (crash ##{info.crash_count})" }
            sleep info.restart_delay_ms.milliseconds
            @total_restarts.add(1_i64)
          end
        end
      end
    end
  end

  # =============================================================================
  # Helper Module for Easy Access
  # =============================================================================
  module Isolated
    def self.spawn(name : String, &block : ->)
      PanicIsolator.instance.spawn_isolated(name, &block)
    end

    def self.spawn_with_retry(name : String, max_retries : Int32 = 3, &block : ->)
      PanicIsolator.instance.spawn_with_retry(name, max_retries, &block)
    end

    def self.stop(name : String)
      PanicIsolator.instance.stop_fiber(name)
    end

    def self.stats
      PanicIsolator.instance.stats
    end
  end
end
