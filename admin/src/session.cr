require "random/secure"

module AdminPanel
  class SessionManager
    Log = ::Log.for("session")

    COOKIE_NAME = "waf_admin_session"

    getter session_ttl : Time::Span

    def initialize(@db : Database, @session_ttl : Time::Span = 24.hours)
    end

    # Create new session for user
    def create_session(user_id : Int64, ip_address : String? = nil, user_agent : String? = nil) : String
      token = Random::Secure.hex(32)
      expires_at = Time.utc + @session_ttl

      @db.create_session(token, user_id, expires_at, ip_address, user_agent)
      Log.debug { "Session created for user #{user_id}" }

      token
    end

    # Get session by token
    def get_session(token : String) : SessionRecord?
      @db.find_session(token)
    end

    # Validate session and return user
    def validate_session(token : String) : UserRecord?
      session = @db.find_session(token)
      return nil unless session
      return nil if session.expired?

      @db.find_user_by_id(session.user_id)
    end

    # Destroy session
    def destroy_session(token : String)
      @db.delete_session(token)
      Log.debug { "Session destroyed: #{token[0..8]}..." }
    end

    # Destroy all sessions for user
    def destroy_user_sessions(user_id : Int64)
      @db.delete_user_sessions(user_id)
      Log.debug { "All sessions destroyed for user #{user_id}" }
    end

    # Get session token from request
    def get_token_from_request(env : HTTP::Server::Context) : String?
      # Try cookie first
      if cookie = env.request.cookies[COOKIE_NAME]?
        return cookie.value unless cookie.value.empty?
      end

      # Try Authorization header (Bearer token)
      if auth_header = env.request.headers["Authorization"]?
        if auth_header.starts_with?("Bearer ")
          return auth_header[7..]
        end
      end

      nil
    end

    # Set session cookie
    def set_cookie(env : HTTP::Server::Context, token : String, secure : Bool = false)
      cookie = HTTP::Cookie.new(
        name: COOKIE_NAME,
        value: token,
        path: "/",
        expires: Time.utc + @session_ttl,
        http_only: true,
        secure: secure,
        samesite: HTTP::Cookie::SameSite::Lax
      )
      env.response.cookies << cookie
    end

    # Clear session cookie
    def clear_cookie(env : HTTP::Server::Context)
      cookie = HTTP::Cookie.new(
        name: COOKIE_NAME,
        value: "",
        path: "/",
        expires: Time.utc - 1.day,
        http_only: true
      )
      env.response.cookies << cookie
    end
  end
end
