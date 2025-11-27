require "file"

module KemalWAF
  # Log rotation yöneticisi
  class LogRotator
    Log = ::Log.for("log_rotator")

    @log_dir : String
    @max_size_mb : Int32
    @retention_days : Int32

    def initialize(@log_dir : String, @max_size_mb : Int32, @retention_days : Int32)
      # Log dizinini oluştur
      Dir.mkdir_p(@log_dir) unless Dir.exists?(@log_dir)
    end

    # Date-based dosya ismi oluştur
    def get_current_log_file(base_name : String, date : Time = Time.local) : String
      date_str = date.to_s("%Y-%m-%d")
      File.join(@log_dir, "#{base_name}-#{date_str}.log")
    end

    # Dosya boyutunu MB cinsinden döndür
    def get_file_size_mb(file_path : String) : Float64
      return 0.0 unless File.exists?(file_path)

      begin
        size_bytes = File.info(file_path).size
        size_bytes.to_f / (1024.0 * 1024.0)
      rescue
        0.0
      end
    end

    # Rotation gerekip gerekmediğini kontrol et
    def should_rotate?(file_path : String, current_date : Time = Time.local) : Bool
      return false unless File.exists?(file_path)

      # Günlük rotation kontrolü
      file_date = File.info(file_path).modification_time.to_s("%Y-%m-%d")
      current_date_str = current_date.to_s("%Y-%m-%d")
      return true if file_date != current_date_str

      # Size-based rotation kontrolü
      size_mb = get_file_size_mb(file_path)
      return true if size_mb >= @max_size_mb

      false
    end

    # Size-based rotation için yeni dosya ismi oluştur
    def get_rotated_file_name(base_file_path : String, current_date : Time = Time.local) : String
      base_name = File.basename(base_file_path, ".log")
      # Tarih kısmını çıkar
      if base_name =~ /^(.+)-(\d{4}-\d{2}-\d{2})(?:-(\d+))?$/
        prefix = $1
        date_part = $2
        counter = $3 ? $3.to_i : 0
        new_counter = counter + 1
        File.join(@log_dir, "#{prefix}-#{date_part}-#{new_counter}.log")
      else
        # İlk rotation
        date_str = current_date.to_s("%Y-%m-%d")
        File.join(@log_dir, "#{base_name}-#{date_str}-1.log")
      end
    end

    # Dosya rotation işlemi
    def rotate_log_file(file_path : String, current_date : Time = Time.local) : String?
      return nil unless File.exists?(file_path)

      begin
        file_date = File.info(file_path).modification_time.to_s("%Y-%m-%d")
        current_date_str = current_date.to_s("%Y-%m-%d")

        if file_date != current_date_str
          # Günlük rotation - yeni tarihli dosya oluştur
          base_name = File.basename(file_path, ".log")
          # Tarih kısmını çıkar
          if base_name =~ /^(.+)-(\d{4}-\d{2}-\d{2})(?:-(\d+))?$/
            prefix = $1
            new_file_path = get_current_log_file(prefix, current_date)
          else
            # İlk kez rotation
            new_file_path = get_current_log_file(base_name, current_date)
          end
        else
          # Size-based rotation
          new_file_path = get_rotated_file_name(file_path, current_date)
        end

        # Dosyayı taşı
        File.rename(file_path, new_file_path)
        Log.info { "Log dosyası rotate edildi: #{file_path} -> #{new_file_path}" }
        new_file_path
      rescue ex
        Log.error { "Log rotation hatası: #{ex.message}" }
        nil
      end
    end

    # Eski log dosyalarını temizle
    def cleanup_old_logs(base_name : String, current_date : Time = Time.local)
      cutoff_date = current_date - @retention_days.days

      begin
        pattern = File.join(@log_dir, "#{base_name}-*.log")
        Dir.glob(pattern).each do |file_path|
          begin
            file_date = File.info(file_path).modification_time
            if file_date < cutoff_date
              File.delete(file_path)
              Log.info { "Eski log dosyası silindi: #{file_path}" }
            end
          rescue ex
            Log.warn { "Log temizleme hatası #{file_path}: #{ex.message}" }
          end
        end
      rescue ex
        Log.error { "Log cleanup hatası: #{ex.message}" }
      end
    end

    # Mevcut log dosyasını döndür (rotation gerekirse yapar)
    def ensure_log_file(base_name : String, current_date : Time = Time.local) : String
      file_path = get_current_log_file(base_name, current_date)

      if should_rotate?(file_path, current_date)
        rotate_log_file(file_path, current_date)
        # Rotation sonrası yeni dosya
        file_path = get_current_log_file(base_name, current_date)
      end

      file_path
    end
  end
end
