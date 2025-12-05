require "sqlite3"
require "json"

module AdminPanel
  class Database
    Log = ::Log.for("database")

    SCHEMA_VERSION = 1

    getter db : DB::Database

    def initialize(db_path : String)
      # Ensure data directory exists
      dir = File.dirname(db_path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      @db = DB.open("sqlite3://#{db_path}")
      run_migrations
    end

    def close
      @db.close
    end

    private def run_migrations
      # Create schema_version table if not exists
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS schema_version (
          version INTEGER PRIMARY KEY
        )
      SQL

      current_version = get_schema_version

      if current_version < 1
        migrate_v1
        set_schema_version(1)
      end

      Log.info { "Database schema version: #{get_schema_version}" }
    end

    private def get_schema_version : Int32
      result = @db.query_one?("SELECT version FROM schema_version ORDER BY version DESC LIMIT 1", as: Int32)
      result || 0
    end

    private def set_schema_version(version : Int32)
      @db.exec("INSERT INTO schema_version (version) VALUES (?)", version)
    end

    private def migrate_v1
      Log.info { "Running migration v1..." }

      # Users table
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT UNIQUE NOT NULL,
          password_hash TEXT NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          last_login DATETIME
        )
      SQL

      # Sessions table
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL,
          expires_at DATETIME NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          ip_address TEXT,
          user_agent TEXT,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      SQL

      # Audit logs table
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS audit_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER,
          action TEXT NOT NULL,
          details TEXT,
          ip_address TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
        )
      SQL

      # Create indexes
      @db.exec "CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at)"

      Log.info { "Migration v1 completed" }
    end

    # User operations
    def user_count : Int64
      @db.query_one("SELECT COUNT(*) FROM users", as: Int64)
    end

    def setup_required? : Bool
      user_count == 0
    end

    def create_user(email : String, password_hash : String) : Int64
      @db.exec("INSERT INTO users (email, password_hash) VALUES (?, ?)", email, password_hash)
      @db.scalar("SELECT last_insert_rowid()").as(Int64)
    end

    def find_user_by_email(email : String) : UserRecord?
      @db.query_one?(
        "SELECT id, email, password_hash, created_at, last_login FROM users WHERE email = ?",
        email,
        as: {Int64, String, String, Time, Time?}
      ).try do |row|
        UserRecord.new(
          id: row[0],
          email: row[1],
          password_hash: row[2],
          created_at: row[3],
          last_login: row[4]
        )
      end
    end

    def find_user_by_id(id : Int64) : UserRecord?
      @db.query_one?(
        "SELECT id, email, password_hash, created_at, last_login FROM users WHERE id = ?",
        id,
        as: {Int64, String, String, Time, Time?}
      ).try do |row|
        UserRecord.new(
          id: row[0],
          email: row[1],
          password_hash: row[2],
          created_at: row[3],
          last_login: row[4]
        )
      end
    end

    def update_user_last_login(user_id : Int64)
      @db.exec("UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?", user_id)
    end

    # Session operations
    def create_session(id : String, user_id : Int64, expires_at : Time, ip_address : String? = nil, user_agent : String? = nil)
      @db.exec(
        "INSERT INTO sessions (id, user_id, expires_at, ip_address, user_agent) VALUES (?, ?, ?, ?, ?)",
        id, user_id, expires_at, ip_address, user_agent
      )
    end

    def find_session(id : String) : SessionRecord?
      @db.query_one?(
        "SELECT id, user_id, expires_at, created_at, ip_address, user_agent FROM sessions WHERE id = ? AND expires_at > CURRENT_TIMESTAMP",
        id,
        as: {String, Int64, Time, Time, String?, String?}
      ).try do |row|
        SessionRecord.new(
          id: row[0],
          user_id: row[1],
          expires_at: row[2],
          created_at: row[3],
          ip_address: row[4],
          user_agent: row[5]
        )
      end
    end

    def delete_session(id : String)
      @db.exec("DELETE FROM sessions WHERE id = ?", id)
    end

    def delete_user_sessions(user_id : Int64)
      @db.exec("DELETE FROM sessions WHERE user_id = ?", user_id)
    end

    def cleanup_expired_sessions
      result = @db.exec("DELETE FROM sessions WHERE expires_at <= CURRENT_TIMESTAMP")
      Log.debug { "Cleaned up expired sessions" }
    end

    # Audit log operations
    def log_audit(user_id : Int64?, action : String, details : String? = nil, ip_address : String? = nil)
      @db.exec(
        "INSERT INTO audit_logs (user_id, action, details, ip_address) VALUES (?, ?, ?, ?)",
        user_id, action, details, ip_address
      )
    end

    def get_audit_logs(limit : Int32 = 100, offset : Int32 = 0) : Array(AuditLogRecord)
      logs = [] of AuditLogRecord
      @db.query(
        "SELECT id, user_id, action, details, ip_address, created_at FROM audit_logs ORDER BY created_at DESC LIMIT ? OFFSET ?",
        limit, offset
      ) do |rs|
        rs.each do
          logs << AuditLogRecord.new(
            id: rs.read(Int64),
            user_id: rs.read(Int64?),
            action: rs.read(String),
            details: rs.read(String?),
            ip_address: rs.read(String?),
            created_at: rs.read(Time)
          )
        end
      end
      logs
    end
  end

  # Record types
  struct UserRecord
    include JSON::Serializable

    getter id : Int64
    getter email : String
    @[JSON::Field(ignore: true)]
    getter password_hash : String
    getter created_at : Time
    getter last_login : Time?

    def initialize(@id, @email, @password_hash, @created_at, @last_login)
    end
  end

  struct SessionRecord
    getter id : String
    getter user_id : Int64
    getter expires_at : Time
    getter created_at : Time
    getter ip_address : String?
    getter user_agent : String?

    def initialize(@id, @user_id, @expires_at, @created_at, @ip_address, @user_agent)
    end

    def expired? : Bool
      expires_at <= Time.utc
    end
  end

  struct AuditLogRecord
    include JSON::Serializable

    getter id : Int64
    getter user_id : Int64?
    getter action : String
    getter details : String?
    getter ip_address : String?
    getter created_at : Time

    def initialize(@id, @user_id, @action, @details, @ip_address, @created_at)
    end
  end
end
