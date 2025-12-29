require "json"
require "http/web_socket"

module AdminPanel
  module LogsAPI
    Log = ::Log.for("logs_api")

    # Domain adını sanitize et (dosya adı için)
    private def self.sanitize_domain(domain : String) : String
      domain.gsub(/[^a-zA-Z0-9\-]/, "-").downcase
    end

    # Log dosyası yolunu bul
    private def self.get_log_file_path(domain : String, date : Time? = nil) : String?
      sanitized = sanitize_domain(domain)
      date_str = (date || Time.local).to_s("%Y-%m-%d")
      filename = "waf-#{sanitized}-#{date_str}.log"

      # Try multiple possible log directories
      possible_dirs = [
        ENV.fetch("LOG_DIR", "logs"),
        "../logs",
        "logs",
        "/app/logs",
        "/app/waf/logs",
      ]

      Log.debug { "Looking for log file: #{filename} (domain: #{domain}, sanitized: #{sanitized})" }

      possible_dirs.each do |log_dir|
        file_path = File.join(log_dir, filename)
        if File.exists?(file_path)
          Log.info { "Found log file: #{file_path}" }
          return file_path
        end
      end

      # Try today's date if different
      today_str = Time.local.to_s("%Y-%m-%d")
      if today_str != date_str
        today_filename = "waf-#{sanitized}-#{today_str}.log"
        possible_dirs.each do |log_dir|
          file_path = File.join(log_dir, today_filename)
          if File.exists?(file_path)
            Log.info { "Found today's log file: #{file_path}" }
            return file_path
          end
        end
      end

      Log.warn { "Log file not found for domain #{domain} in any of these directories: #{possible_dirs.join(", ")}" }
      nil
    end

    # Son N satırı oku (tail benzeri, performanslı)
    private def self.read_last_n_lines(file_path : String, n : Int32) : Array(String)
      return [] of String unless File.exists?(file_path)

      file_size = File.info(file_path).size
      return [] of String if file_size == 0

      # Küçük dosyalar için basit okuma (1MB'dan küçükse)
      if file_size < 1024 * 1024
        begin
          all_lines = File.read_lines(file_path)
          return all_lines.last(n)
        rescue ex
          Log.error { "Error reading log file: #{ex.message}" }
          return [] of String
        end
      end

      # Büyük dosyalar için geriye doğru okuma
      lines = [] of String
      file = File.open(file_path, "r")

      begin
        # Dosyanın sonundan başlayarak geriye doğru oku
        position = file_size
        chunk_size = 16384 # 16KB chunks
        buffer = Bytes.new(chunk_size)
        temp_lines = [] of String
        line_buffer = IO::Memory.new

        while position > 0 && temp_lines.size < n
          read_size = Math.min(chunk_size, position)
          position -= read_size
          file.seek(position)

          bytes_read = file.read(buffer[0, read_size])
          break if bytes_read == 0

          # Buffer'ı geriye doğru işle
          (bytes_read - 1).downto(0) do |i|
            char = buffer[i].chr
            if char == '\n'
              if line_buffer.size > 0
                # Satırı tersine çevir ve ekle
                line_str = line_buffer.to_s.reverse
                temp_lines << line_str
                line_buffer.clear
                break if temp_lines.size >= n
              end
            else
              line_buffer << char
            end
          end
        end

        # Son satırı ekle (eğer varsa ve dosyanın başındaysak)
        if line_buffer.size > 0 && temp_lines.size < n
          line_str = line_buffer.to_s.reverse
          temp_lines << line_str
        end

        # Tersine çevir (en yeni önce)
        lines = temp_lines.reverse
      rescue ex
        Log.error { "Error reading log file: #{ex.message}" }
        Log.debug { ex.backtrace.join("\n") if ex.backtrace }
      ensure
        file.close
      end

      lines
    end

    # Domain için mevcut log dosyalarını listele
    private def self.list_log_files(domain : String) : Array(Hash(String, String | Int64))
      sanitized = sanitize_domain(domain)
      log_dir = ENV.fetch("LOG_DIR", "logs")
      pattern = File.join(log_dir, "waf-#{sanitized}-*.log")

      files = [] of Hash(String, String | Int64)

      begin
        Dir.glob(pattern).each do |file_path|
          begin
            file_info = File.info(file_path)
            # Dosya adından tarihi çıkar
            basename = File.basename(file_path, ".log")
            if basename =~ /waf-#{sanitized}-(\d{4}-\d{2}-\d{2})/
              date_str = $1
              files << {
                "date" => date_str,
                "size" => file_info.size.to_i64,
                "path" => file_path,
              }
            end
          rescue
            # Skip files that can't be read
          end
        end
      rescue
        # Directory doesn't exist or can't be accessed
      end

      # Tarihe göre sırala (en yeni önce)
      files.sort_by { |f| f["date"].as(String) }.reverse
    end

    def self.setup(app : Application)
      # Get domain logs (REST API)
      get "/api/logs/domains/:domain" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])
        limit = env.params.query["limit"]?.try(&.to_i) || 100
        offset = env.params.query["offset"]?.try(&.to_i) || 0

        # Limit kontrolü (max 1000)
        limit = Math.min(limit, 1000)
        limit = Math.max(limit, 1)

        begin
          # Bugünün log dosyasını oku
          file_path = get_log_file_path(domain)
          Log.info { "REST API: Looking for log file for domain #{domain}: #{file_path}" }

          unless file_path
            Log.warn { "REST API: Log file not found for domain #{domain}" }
            env.response.status_code = 404
            next {error: "Log file not found for domain"}.to_json
          end

          Log.info { "REST API: Reading logs from #{file_path}" }

          # Son N satırı oku
          lines = read_last_n_lines(file_path, limit + offset)
          Log.info { "REST API: Read #{lines.size} lines from file" }

          # Offset uygula
          if offset > 0 && offset < lines.size
            lines = lines[0, lines.size - offset]
          end

          # JSON parse et
          logs = [] of JSON::Any
          lines.each do |line|
            begin
              parsed = JSON.parse(line)
              logs << parsed
            rescue ex
              Log.debug { "REST API: Skip invalid JSON line: #{ex.message}" }
            end
          end

          # Tersine çevir (en yeni önce)
          logs = logs.reverse

          Log.info { "REST API: Returning #{logs.size} log entries" }

          {
            logs:     logs,
            total:    logs.size,
            has_more: lines.size >= (limit + offset),
          }.to_json
        rescue ex
          Log.error { "Error reading logs: #{ex.message}" }
          Log.debug { ex.backtrace.join("\n") if ex.backtrace }
          env.response.status_code = 500
          {error: "Failed to read logs: #{ex.message}"}.to_json
        end
      end

      # List log files for domain
      get "/api/logs/domains/:domain/files" do |env|
        env.response.content_type = "application/json"

        user = AdminPanel.require_auth(env, app.db)
        next unless user

        domain = URI.decode(env.params.url["domain"])

        begin
          files = list_log_files(domain)
          {files: files}.to_json
        rescue ex
          Log.error { "Error listing log files: #{ex.message}" }
          env.response.status_code = 500
          {error: "Failed to list log files: #{ex.message}"}.to_json
        end
      end

      # WebSocket endpoint for live log streaming
      ws "/api/logs/domains/:domain/stream" do |socket, env|
        # Authentication check
        token = app.session_manager.get_token_from_request(env)

        unless token
          socket.close
          next
        end

        # Validate session
        user = app.session_manager.validate_session(token)
        unless user
          socket.close
          next
        end

        domain_param = env.params.url["domain"]?
        unless domain_param
          socket.close
          next
        end
        domain = URI.decode(domain_param)

        Log.info { "WebSocket connection opened for domain: #{domain} (user: #{user.email})" }

        # Initial logs gönder (son 100 satır)
        file_path = nil
        begin
          file_path = get_log_file_path(domain)
          Log.info { "Initial log file path for domain #{domain}: #{file_path}" }
          if file_path && File.exists?(file_path)
            lines = read_last_n_lines(file_path, 100)
            Log.info { "Read #{lines.size} lines from log file" }
            lines.reverse.each do |line|
              begin
                parsed = JSON.parse(line)
                socket.send({
                  type: "log_entry",
                  data: parsed,
                }.to_json)
              rescue ex
                Log.debug { "Skip invalid JSON line: #{ex.message}" }
              end
            end
          else
            Log.warn { "Log file not found or doesn't exist: #{file_path}" }
          end
        rescue ex
          Log.error { "Error sending initial logs: #{ex.message}" }
          Log.debug { ex.backtrace.join("\n") if ex.backtrace }
        end

        # Log dosyasını izle (polling)
        last_position = 0
        last_file_path = file_path

        spawn do
          loop do
            break if socket.closed?

            begin
              current_file_path = get_log_file_path(domain) || last_file_path

              # Dosya değiştiyse (rotation) position'ı sıfırla
              if current_file_path != last_file_path
                last_position = 0
                last_file_path = current_file_path
              end

              if current_file_path && File.exists?(current_file_path)
                file = File.open(current_file_path, "r")
                file_size = File.info(current_file_path).size

                # Yeni satırlar varsa oku
                if file_size > last_position
                  file.seek(last_position)

                  file.each_line do |line|
                    begin
                      parsed = JSON.parse(line)
                      socket.send({
                        type: "log_entry",
                        data: parsed,
                      }.to_json)
                    rescue
                      # Skip invalid JSON
                    end
                  end

                  last_position = file_size
                end

                file.close
              end

              # 500ms bekle (polling interval)
              sleep 500.milliseconds
            rescue ex
              Log.error { "Error in log streaming: #{ex.message}" }
              sleep 1.second
            end
          end
        end

        # Connection kapandığında cleanup
        socket.on_close do
          Log.info { "WebSocket connection closed for domain: #{domain}" }
        end
      end
    end
  end
end
