require "crypto/bcrypt/password"
require "random/secure"

module AdminPanel
  class Auth
    Log = ::Log.for("auth")

    # Password requirements
    MIN_PASSWORD_LENGTH = 8

    def initialize(@db : Database)
    end

    # Hash password using bcrypt
    def hash_password(password : String) : String
      Crypto::Bcrypt::Password.create(password, cost: 12).to_s
    end

    # Verify password against hash
    def verify_password(password : String, hash : String) : Bool
      bcrypt = Crypto::Bcrypt::Password.new(hash)
      bcrypt.verify(password)
    rescue
      false
    end

    # Generate secure session token
    def generate_token : String
      Random::Secure.hex(32)
    end

    # Validate email format
    def valid_email?(email : String) : Bool
      email.matches?(/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)
    end

    # Validate password strength
    def valid_password?(password : String) : {Bool, String?}
      if password.size < MIN_PASSWORD_LENGTH
        return {false, "Password must be at least #{MIN_PASSWORD_LENGTH} characters"}
      end

      unless password.matches?(/[a-z]/)
        return {false, "Password must contain at least one lowercase letter"}
      end

      unless password.matches?(/[A-Z]/)
        return {false, "Password must contain at least one uppercase letter"}
      end

      unless password.matches?(/[0-9]/)
        return {false, "Password must contain at least one number"}
      end

      {true, nil}
    end

    # Register new user (only during setup)
    def register(email : String, password : String) : {Bool, String?, Int64?}
      # Validate email
      unless valid_email?(email)
        return {false, "Invalid email format", nil}
      end

      # Validate password
      valid, error = valid_password?(password)
      unless valid
        return {false, error, nil}
      end

      # Check if user already exists
      if @db.find_user_by_email(email)
        return {false, "Email already registered", nil}
      end

      # Create user
      password_hash = hash_password(password)
      user_id = @db.create_user(email, password_hash)

      Log.info { "User registered: #{email}" }
      {true, nil, user_id}
    end

    # Login user
    def login(email : String, password : String) : {Bool, String?, UserRecord?}
      user = @db.find_user_by_email(email)

      unless user
        Log.warn { "Login failed: user not found (#{email})" }
        return {false, "Invalid email or password", nil}
      end

      unless verify_password(password, user.password_hash)
        Log.warn { "Login failed: invalid password (#{email})" }
        return {false, "Invalid email or password", nil}
      end

      # Update last login
      @db.update_user_last_login(user.id)

      Log.info { "User logged in: #{email}" }
      {true, nil, user}
    end

    # Get user by session token
    def get_user_by_session(token : String) : UserRecord?
      session = @db.find_session(token)
      return nil unless session
      return nil if session.expired?

      @db.find_user_by_id(session.user_id)
    end
  end
end
