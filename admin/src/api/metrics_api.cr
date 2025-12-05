require "http/client"

module AdminPanel
  module MetricsAPI
    def self.setup(app : Application)
      # Proxy metrics from WAF
      get "/api/metrics" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        # Get WAF config to find metrics port
        config = app.config_manager.read_config

        # Default metrics port (from WAF config)
        metrics_port = 9090 # Default, could be read from config

        begin
          # Fetch metrics from WAF
          client = HTTP::Client.new("localhost", metrics_port)
          client.connect_timeout = 2.seconds
          client.read_timeout = 5.seconds

          response = client.get("/metrics")

          if response.status_code == 200
            # Parse Prometheus metrics
            metrics = parse_prometheus_metrics(response.body)
            metrics.to_json
          else
            env.response.status_code = 502
            {error: "Failed to fetch metrics from WAF"}.to_json
          end
        rescue ex : Socket::ConnectError | IO::TimeoutError
          # WAF metrics not available
          {
            available:            false,
            message:              "WAF metrics not available",
            total_requests:       0,
            blocked_requests:     0,
            allowed_requests:     0,
            requests_per_second:  0.0,
            avg_response_time_ms: 0.0,
            active_connections:   0,
            uptime_seconds:       0,
          }.to_json
        ensure
          client.try(&.close)
        end
      end

      # Get dashboard stats
      get "/api/stats" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domains = app.config_manager.get_domains

        # Count SSL enabled domains
        ssl_enabled = domains.count { |_, c| c.letsencrypt_enabled || !c.cert_file.nil? }

        # Try to get WAF metrics
        waf_stats = fetch_waf_stats

        {
          hosts: {
            total:       domains.size,
            ssl_enabled: ssl_enabled,
          },
          requests: {
            total:   waf_stats[:total_requests],
            blocked: waf_stats[:blocked_requests],
            allowed: waf_stats[:total_requests] - waf_stats[:blocked_requests],
          },
          performance: {
            requests_per_second:  waf_stats[:requests_per_second],
            avg_response_time_ms: waf_stats[:avg_response_time_ms],
          },
          uptime_seconds: waf_stats[:uptime_seconds],
          waf_available:  waf_stats[:available],
        }.to_json
      end
    end

    private def self.parse_prometheus_metrics(body : String) : Hash(String, Float64 | Int64 | String | Bool)
      metrics = {} of String => Float64 | Int64 | String | Bool
      metrics["available"] = true

      body.each_line do |line|
        next if line.starts_with?("#") || line.empty?

        if match = line.match(/^(\w+)(?:\{[^}]*\})?\s+(.+)$/)
          name = match[1]
          value = match[2]

          case name
          when "waf_requests_total"
            metrics["total_requests"] = value.to_i64
          when "waf_blocked_requests_total"
            metrics["blocked_requests"] = value.to_i64
          when "waf_request_duration_seconds_sum"
            metrics["response_time_sum"] = value.to_f64
          when "waf_request_duration_seconds_count"
            metrics["response_time_count"] = value.to_i64
          when "waf_active_connections"
            metrics["active_connections"] = value.to_i64
          when "process_start_time_seconds"
            start_time = value.to_f64
            metrics["uptime_seconds"] = (Time.utc.to_unix - start_time).to_i64
          end
        end
      end

      # Calculate derived metrics
      total = metrics["total_requests"]?.try(&.as(Int64)) || 0_i64
      blocked = metrics["blocked_requests"]?.try(&.as(Int64)) || 0_i64
      metrics["allowed_requests"] = total - blocked

      # Calculate average response time
      sum = metrics["response_time_sum"]?.try(&.as(Float64)) || 0.0
      count = metrics["response_time_count"]?.try(&.as(Int64)) || 1_i64
      metrics["avg_response_time_ms"] = (sum / count * 1000).round(2)

      # Estimate requests per second (simplified)
      uptime = metrics["uptime_seconds"]?.try(&.as(Int64)) || 1_i64
      metrics["requests_per_second"] = (total.to_f / uptime).round(2)

      metrics
    end

    private def self.fetch_waf_stats : NamedTuple(
      available: Bool,
      total_requests: Int64,
      blocked_requests: Int64,
      requests_per_second: Float64,
      avg_response_time_ms: Float64,
      uptime_seconds: Int64)
      begin
        client = HTTP::Client.new("localhost", 9090)
        client.connect_timeout = 2.seconds
        client.read_timeout = 5.seconds

        response = client.get("/metrics")

        if response.status_code == 200
          metrics = parse_prometheus_metrics(response.body)
          {
            available:            true,
            total_requests:       metrics["total_requests"]?.try(&.as(Int64)) || 0_i64,
            blocked_requests:     metrics["blocked_requests"]?.try(&.as(Int64)) || 0_i64,
            requests_per_second:  metrics["requests_per_second"]?.try(&.as(Float64)) || 0.0,
            avg_response_time_ms: metrics["avg_response_time_ms"]?.try(&.as(Float64)) || 0.0,
            uptime_seconds:       metrics["uptime_seconds"]?.try(&.as(Int64)) || 0_i64,
          }
        else
          default_stats
        end
      rescue
        default_stats
      ensure
        client.try(&.close)
      end
    end

    private def self.default_stats
      {
        available:            false,
        total_requests:       0_i64,
        blocked_requests:     0_i64,
        requests_per_second:  0.0,
        avg_response_time_ms: 0.0,
        uptime_seconds:       0_i64,
      }
    end
  end
end
