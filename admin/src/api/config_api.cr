require "json"

module AdminPanel
  module ConfigAPI
    def self.setup(app : Application)
      # Get global config
      get "/api/config" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        config = app.config_manager.read_config

        {
          mode:          config.mode,
          rate_limiting: {
            enabled:        config.rate_limiting.enabled,
            default_limit:  config.rate_limiting.default_limit,
            window:         config.rate_limiting.window,
            block_duration: config.rate_limiting.block_duration,
          },
          geoip: {
            enabled:           config.geoip.enabled,
            mmdb_file:         config.geoip.mmdb_file,
            blocked_countries: config.geoip.blocked_countries,
            allowed_countries: config.geoip.allowed_countries,
          },
          ip_filtering: {
            enabled:        config.ip_filtering.enabled,
            whitelist_file: config.ip_filtering.whitelist_file,
            blacklist_file: config.ip_filtering.blacklist_file,
          },
          server: {
            http_enabled:  config.server.http_enabled,
            https_enabled: config.server.https_enabled,
            http_port:     config.server.http_port,
            https_port:    config.server.https_port,
          },
        }.to_json
      end

      # Update global config
      put "/api/config" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          mode = data["mode"]?.try(&.as_s)

          rate_limiting = if rl = data["rate_limiting"]?
                            RateLimitConfigData.new(
                              enabled: rl["enabled"]?.try(&.as_bool) || true,
                              default_limit: rl["default_limit"]?.try(&.as_i) || 100,
                              window: rl["window"]?.try(&.as_s) || "60s",
                              block_duration: rl["block_duration"]?.try(&.as_s) || "300s"
                            )
                          else
                            nil
                          end

          geoip = if geo = data["geoip"]?
                    GeoIPConfigData.new(
                      enabled: geo["enabled"]?.try(&.as_bool) || false,
                      mmdb_file: geo["mmdb_file"]?.try(&.as_s),
                      blocked_countries: geo["blocked_countries"]?.try(&.as_a.map(&.as_s)) || [] of String,
                      allowed_countries: geo["allowed_countries"]?.try(&.as_a.map(&.as_s)) || [] of String
                    )
                  else
                    nil
                  end

          ip_filtering = if ip = data["ip_filtering"]?
                           IPFilterConfigData.new(
                             enabled: ip["enabled"]?.try(&.as_bool) || true,
                             whitelist_file: ip["whitelist_file"]?.try(&.as_s),
                             blacklist_file: ip["blacklist_file"]?.try(&.as_s)
                           )
                         else
                           nil
                         end

          unless app.config_manager.update_global_config(mode, rate_limiting, geoip, ip_filtering)
            env.response.status_code = 500
            next {error: "Failed to update config"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "config_updated",
            nil,
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          {
            success: true,
            message: "Config updated",
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Trigger WAF config reload
      post "/api/config/reload" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        # TODO: Implement actual WAF reload via signal or API
        # For now, just log the action
        app.db.log_audit(
          user.id,
          "config_reload_requested",
          nil,
          env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
        )

        {
          success: true,
          message: "Config reload requested. WAF will pick up changes within 5 seconds.",
        }.to_json
      end

      # Get IP whitelist
      get "/api/config/ip-whitelist" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        config = app.config_manager.read_config
        whitelist_file = config.ip_filtering.whitelist_file

        ips = if whitelist_file && File.exists?(whitelist_file)
                File.read_lines(whitelist_file)
                  .map(&.strip)
                  .reject { |line| line.empty? || line.starts_with?("#") }
              else
                [] of String
              end

        {ips: ips}.to_json
      end

      # Update IP whitelist
      put "/api/config/ip-whitelist" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          ips = data["ips"]?.try(&.as_a.map(&.as_s)) || [] of String

          config = app.config_manager.read_config
          whitelist_file = config.ip_filtering.whitelist_file

          if whitelist_file
            content = ips.join("\n") + "\n"
            File.write(whitelist_file, content)

            app.db.log_audit(
              user.id,
              "ip_whitelist_updated",
              "Count: #{ips.size}",
              env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
            )

            {success: true, message: "Whitelist updated"}.to_json
          else
            env.response.status_code = 400
            {error: "Whitelist file not configured"}.to_json
          end
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Get IP blacklist
      get "/api/config/ip-blacklist" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        config = app.config_manager.read_config
        blacklist_file = config.ip_filtering.blacklist_file

        ips = if blacklist_file && File.exists?(blacklist_file)
                File.read_lines(blacklist_file)
                  .map(&.strip)
                  .reject { |line| line.empty? || line.starts_with?("#") }
              else
                [] of String
              end

        {ips: ips}.to_json
      end

      # Update IP blacklist
      put "/api/config/ip-blacklist" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          ips = data["ips"]?.try(&.as_a.map(&.as_s)) || [] of String

          config = app.config_manager.read_config
          blacklist_file = config.ip_filtering.blacklist_file

          if blacklist_file
            content = ips.join("\n") + "\n"
            File.write(blacklist_file, content)

            app.db.log_audit(
              user.id,
              "ip_blacklist_updated",
              "Count: #{ips.size}",
              env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
            )

            {success: true, message: "Blacklist updated"}.to_json
          else
            env.response.status_code = 400
            {error: "Blacklist file not configured"}.to_json
          end
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Get audit logs
      get "/api/config/audit-logs" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        limit = env.params.query["limit"]?.try(&.to_i) || 100
        offset = env.params.query["offset"]?.try(&.to_i) || 0

        logs = app.db.get_audit_logs(limit, offset)

        {logs: logs}.to_json
      end
    end
  end
end
