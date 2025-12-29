require "json"

module AdminPanel
  module HostsAPI
    def self.setup(app : Application)
      # List all proxy hosts
      get "/api/hosts" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domains = app.config_manager.get_domains
        hosts = domains.map do |domain, config|
          {
            domain:                 domain,
            default_upstream:       config.default_upstream,
            upstream_host_header:   config.upstream_host_header,
            preserve_original_host: config.preserve_original_host,
            verify_ssl:             config.verify_ssl,
            ssl:                    {
              enabled:           config.letsencrypt_enabled || !config.cert_file.nil?,
              type:              detect_ssl_type(config),
              letsencrypt_email: config.letsencrypt_email,
              cert_file:         config.cert_file,
              key_file:          config.key_file,
            },
            status: "online", # TODO: Real health check
          }
        end

        {hosts: hosts}.to_json
      end

      # Get single proxy host
      get "/api/hosts/:domain" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])
        config = app.config_manager.get_domain(domain)

        unless config
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        {
          domain:                 domain,
          default_upstream:       config.default_upstream,
          upstream_host_header:   config.upstream_host_header,
          preserve_original_host: config.preserve_original_host,
          verify_ssl:             config.verify_ssl,
          ssl:                    {
            enabled:           config.letsencrypt_enabled || !config.cert_file.nil?,
            type:              detect_ssl_type(config),
            letsencrypt_email: config.letsencrypt_email,
            cert_file:         config.cert_file,
            key_file:          config.key_file,
          },
        }.to_json
      end

      # Create proxy host
      post "/api/hosts" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          domain = data["domain"]?.try(&.as_s) || ""
          upstream = data["upstream_url"]?.try(&.as_s) || ""

          if domain.empty? || upstream.empty?
            env.response.status_code = 400
            next {error: "Domain and upstream_url are required"}.to_json
          end

          # Check if domain already exists
          if app.config_manager.get_domain(domain)
            env.response.status_code = 409
            next {error: "Domain already exists"}.to_json
          end

          # Build domain config
          ssl_type = data["ssl_type"]?.try(&.as_s) || "none"

          # Validate Let's Encrypt email
          ssl_email = data["ssl_email"]?.try(&.as_s)
          if ssl_type == "letsencrypt"
            if !ssl_email || ssl_email.strip.empty?
              env.response.status_code = 400
              next {error: "Email address is required for Let's Encrypt certificates"}.to_json
            end
            ssl_email = ssl_email.strip
          end

          config = DomainConfigData.new(
            default_upstream: upstream,
            upstream_host_header: data["upstream_host_header"]?.try(&.as_s) || domain,
            preserve_original_host: data["preserve_host"]?.try(&.as_bool) || true,
            verify_ssl: data["verify_ssl"]?.try(&.as_bool) || true,
            letsencrypt_enabled: ssl_type == "letsencrypt",
            letsencrypt_email: ssl_email,
            cert_file: ssl_type == "custom" ? data["cert_file"]?.try(&.as_s) : nil,
            key_file: ssl_type == "custom" ? data["key_file"]?.try(&.as_s) : nil
          )

          unless app.config_manager.save_domain(domain, config)
            env.response.status_code = 500
            next {error: "Failed to save domain"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "domain_created",
            "Domain: #{domain}, Upstream: #{upstream}",
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          env.response.status_code = 201
          {
            success: true,
            message: "Domain created",
            domain:  domain,
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Update proxy host
      put "/api/hosts/:domain" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])

        unless app.config_manager.get_domain(domain)
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          upstream = data["upstream_url"]?.try(&.as_s) || ""
          if upstream.empty?
            env.response.status_code = 400
            next {error: "upstream_url is required"}.to_json
          end

          ssl_type = data["ssl_type"]?.try(&.as_s) || "none"

          # Validate Let's Encrypt email
          ssl_email = data["ssl_email"]?.try(&.as_s)
          if ssl_type == "letsencrypt"
            if !ssl_email || ssl_email.strip.empty?
              env.response.status_code = 400
              next {error: "Email address is required for Let's Encrypt certificates"}.to_json
            end
            ssl_email = ssl_email.strip
          end

          config = DomainConfigData.new(
            default_upstream: upstream,
            upstream_host_header: data["upstream_host_header"]?.try(&.as_s) || domain,
            preserve_original_host: data["preserve_host"]?.try(&.as_bool) || true,
            verify_ssl: data["verify_ssl"]?.try(&.as_bool) || true,
            letsencrypt_enabled: ssl_type == "letsencrypt",
            letsencrypt_email: ssl_email,
            cert_file: ssl_type == "custom" ? data["cert_file"]?.try(&.as_s) : nil,
            key_file: ssl_type == "custom" ? data["key_file"]?.try(&.as_s) : nil
          )

          unless app.config_manager.save_domain(domain, config)
            env.response.status_code = 500
            next {error: "Failed to update domain"}.to_json
          end

          # Audit log
          app.db.log_audit(
            user.id,
            "domain_updated",
            "Domain: #{domain}",
            env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
          )

          {
            success: true,
            message: "Domain updated",
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Delete proxy host
      delete "/api/hosts/:domain" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])

        unless app.config_manager.get_domain(domain)
          env.response.status_code = 404
          next {error: "Domain not found"}.to_json
        end

        unless app.config_manager.delete_domain(domain)
          env.response.status_code = 500
          next {error: "Failed to delete domain"}.to_json
        end

        # Audit log
        app.db.log_audit(
          user.id,
          "domain_deleted",
          "Domain: #{domain}",
          env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
        )

        {
          success: true,
          message: "Domain deleted",
        }.to_json
      end
    end

    private def self.detect_ssl_type(config : DomainConfigData) : String
      if config.letsencrypt_enabled
        "letsencrypt"
      elsif config.cert_file && config.key_file
        "custom"
      else
        "none"
      end
    end
  end
end
