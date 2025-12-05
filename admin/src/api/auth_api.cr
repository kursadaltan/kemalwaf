require "json"

module AdminPanel
  module AuthAPI
    def self.setup(app : Application)
      # Check if setup is required
      get "/api/setup/status" do |env|
        env.response.content_type = "application/json"
        {
          setup_required: app.db.setup_required?,
          version:        AdminPanel::VERSION,
        }.to_json
      end

      # Initial setup - create first user
      post "/api/setup" do |env|
        env.response.content_type = "application/json"

        # Only allow if no users exist
        unless app.db.setup_required?
          env.response.status_code = 400
          next {error: "Setup already completed"}.to_json
        end

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          email = data["email"]?.try(&.as_s) || ""
          password = data["password"]?.try(&.as_s) || ""

          if email.empty? || password.empty?
            env.response.status_code = 400
            next {error: "Email and password are required"}.to_json
          end

          success, error, user_id = app.auth.register(email, password)

          unless success
            env.response.status_code = 400
            next {error: error}.to_json
          end

          # Auto-login after setup
          token = ""
          if user_id
            token = app.session_manager.create_session(
              user_id,
              env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s),
              env.request.headers["User-Agent"]?
            )
            app.session_manager.set_cookie(env, token, app.config.cookie_secure)

            # Audit log
            app.db.log_audit(user_id, "setup_completed", "Initial user created")
          end

          {
            success: true,
            message: "Setup completed successfully",
            token:   token,
          }.to_json
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Login
      post "/api/auth/login" do |env|
        env.response.content_type = "application/json"

        begin
          body = env.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          email = data["email"]?.try(&.as_s) || ""
          password = data["password"]?.try(&.as_s) || ""

          if email.empty? || password.empty?
            env.response.status_code = 400
            next {error: "Email and password are required"}.to_json
          end

          success, error, user = app.auth.login(email, password)

          unless success
            env.response.status_code = 401
            # Audit failed login
            app.db.log_audit(
              nil,
              "login_failed",
              "Email: #{email}",
              env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
            )
            next {error: error}.to_json
          end

          if user
            token = app.session_manager.create_session(
              user.id,
              env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s),
              env.request.headers["User-Agent"]?
            )
            app.session_manager.set_cookie(env, token, app.config.cookie_secure)

            # Audit successful login
            app.db.log_audit(
              user.id,
              "login_success",
              nil,
              env.request.headers["X-Forwarded-For"]? || env.request.remote_address.try(&.to_s)
            )

            {
              success: true,
              token:   token,
              user:    {
                id:    user.id,
                email: user.email,
              },
            }.to_json
          else
            env.response.status_code = 500
            {error: "Unexpected error"}.to_json
          end
        rescue ex : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        end
      end

      # Logout
      post "/api/auth/logout" do |env|
        env.response.content_type = "application/json"

        token = app.session_manager.get_token_from_request(env)
        if token
          app.session_manager.destroy_session(token)
        end
        app.session_manager.clear_cookie(env)

        {success: true, message: "Logged out"}.to_json
      end

      # Get current user
      get "/api/auth/me" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        {
          id:         user.id,
          email:      user.email,
          created_at: user.created_at.to_rfc3339,
          last_login: user.last_login.try(&.to_rfc3339),
        }.to_json
      end
    end
  end
end
