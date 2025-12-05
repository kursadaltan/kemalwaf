module AdminPanel
  # Auth middleware - adds current_user_id to context
  class AuthMiddleware < Kemal::Handler
    def initialize(@app : Application)
    end

    def call(env)
      # Skip auth for public endpoints
      path = env.request.path
      if public_path?(path)
        return call_next(env)
      end

      # Get session token
      token = @app.session_manager.get_token_from_request(env)

      if token
        Log.debug { "Token found: #{token[0..10]}..." }
        # Validate session and get user
        if user = @app.session_manager.validate_session(token)
          Log.debug { "User validated: #{user.id}" }
          env.set("current_user_id", user.id.to_s)
        else
          Log.debug { "Session validation failed for token" }
        end
      else
        Log.debug { "No token found in request" }
      end

      call_next(env)
    end

    private def public_path?(path : String) : Bool
      # Public paths that don't require auth
      public_paths = [
        "/api/setup/status",
        "/api/setup",
        "/api/auth/login",
        "/api/health",
      ]

      public_paths.includes?(path) ||
        !path.starts_with?("/api/") ||
        path.starts_with?("/assets/") ||
        path.ends_with?(".js") ||
        path.ends_with?(".css") ||
        path.ends_with?(".png") ||
        path.ends_with?(".svg") ||
        path.ends_with?(".ico")
    end
  end

  # Helper to require authentication - returns user or halts
  def self.require_auth(env, db : Database) : UserRecord?
    user_id_str = env.get?("current_user_id")

    unless user_id_str.is_a?(String)
      env.response.status_code = 401
      env.response.content_type = "application/json"
      env.response.print({error: "Authentication required"}.to_json)
      return nil
    end

    user_id = user_id_str.to_i64
    user = db.find_user_by_id(user_id)

    unless user
      env.response.status_code = 401
      env.response.content_type = "application/json"
      env.response.print({error: "User not found"}.to_json)
      return nil
    end

    user
  end
end
