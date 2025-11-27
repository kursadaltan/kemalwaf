module KemalWAF
  # Prometheus formatında metrik yöneticisi
  class Metrics
    @requests_total : Atomic(Int64)
    @blocked_total : Atomic(Int64)
    @observed_total : Atomic(Int64)
    @rate_limited_total : Atomic(Int64)
    @rules_loaded : Atomic(Int32)

    def initialize
      @requests_total = Atomic(Int64).new(0_i64)
      @blocked_total = Atomic(Int64).new(0_i64)
      @observed_total = Atomic(Int64).new(0_i64)
      @rate_limited_total = Atomic(Int64).new(0_i64)
      @rules_loaded = Atomic(Int32).new(0)
    end

    def increment_requests
      @requests_total.add(1_i64)
    end

    def increment_blocked
      @blocked_total.add(1_i64)
    end

    def increment_observed
      @observed_total.add(1_i64)
    end

    def increment_rate_limited
      @rate_limited_total.add(1_i64)
    end

    def set_rules_loaded(count : Int32)
      @rules_loaded.set(count)
    end

    def to_prometheus : String
      String.build do |str|
        str << "# HELP waf_requests_total Total number of requests processed\n"
        str << "# TYPE waf_requests_total counter\n"
        str << "waf_requests_total #{@requests_total.get}\n"
        str << "\n"

        str << "# HELP waf_blocked_total Total number of blocked requests\n"
        str << "# TYPE waf_blocked_total counter\n"
        str << "waf_blocked_total #{@blocked_total.get}\n"
        str << "\n"

        str << "# HELP waf_observed_total Total number of observed (not blocked) rule matches\n"
        str << "# TYPE waf_observed_total counter\n"
        str << "waf_observed_total #{@observed_total.get}\n"
        str << "\n"

        str << "# HELP waf_rate_limited_total Total number of rate limited requests\n"
        str << "# TYPE waf_rate_limited_total counter\n"
        str << "waf_rate_limited_total #{@rate_limited_total.get}\n"
        str << "\n"

        str << "# HELP waf_rules_loaded Number of currently loaded rules\n"
        str << "# TYPE waf_rules_loaded gauge\n"
        str << "waf_rules_loaded #{@rules_loaded.get}\n"
      end
    end
  end
end
