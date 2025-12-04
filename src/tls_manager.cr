require "openssl"
require "file_utils"
require "./config_loader"
require "./letsencrypt_manager"

module KemalWAF
  # Domain bazlı sertifika bilgisi
  struct DomainCertificate
    property domain : String
    property cert_file : String
    property key_file : String
    property letsencrypt : Bool
    property loaded_at : Time

    def initialize(@domain : String, @cert_file : String, @key_file : String, @letsencrypt : Bool = false)
      @loaded_at = Time.utc
    end
  end

  # SNI (Server Name Indication) yöneticisi
  # Domain bazlı sertifika yönetimi ve SNI callback fonksiyonu
  class SNIManager
    Log = ::Log.for("sni_manager")

    @domain_certs : Hash(String, DomainCertificate)
    @default_cert : DomainCertificate?
    @cert_dir : String
    @mutex : Mutex

    def initialize(@cert_dir : String = "config/certs")
      @domain_certs = {} of String => DomainCertificate
      @default_cert = nil
      @mutex = Mutex.new
      FileUtils.mkdir_p(@cert_dir)
    end

    # Domain için sertifika ekle
    def add_domain_certificate(domain : String, cert_file : String, key_file : String, letsencrypt : Bool = false) : Bool
      unless File.exists?(cert_file) && File.exists?(key_file)
        Log.error { "Certificate files not found for domain '#{domain}': cert=#{cert_file}, key=#{key_file}" }
        return false
      end

      @mutex.synchronize do
        @domain_certs[domain] = DomainCertificate.new(domain, cert_file, key_file, letsencrypt)
        Log.info { "Certificate added for domain '#{domain}': cert=#{cert_file}" }
      end
      true
    end

    # Varsayılan sertifika ayarla
    def set_default_certificate(cert_file : String, key_file : String) : Bool
      unless File.exists?(cert_file) && File.exists?(key_file)
        Log.error { "Default certificate files not found: cert=#{cert_file}, key=#{key_file}" }
        return false
      end

      @mutex.synchronize do
        @default_cert = DomainCertificate.new("*", cert_file, key_file, false)
        Log.info { "Default certificate set: cert=#{cert_file}" }
      end
      true
    end

    # Domain için sertifika al
    def get_certificate(domain : String) : DomainCertificate?
      @mutex.synchronize do
        # Önce exact match dene
        if cert = @domain_certs[domain]?
          return cert
        end

        # Wildcard match dene (*.example.com için)
        parts = domain.split(".")
        if parts.size >= 2
          wildcard_domain = "*." + parts[1..].join(".")
          if cert = @domain_certs[wildcard_domain]?
            return cert
          end
        end

        # Default sertifika döndür
        @default_cert
      end
    end

    # Tüm domain sertifikalarını listele
    def list_domains : Array(String)
      @mutex.synchronize do
        @domain_certs.keys
      end
    end

    # Domain sertifikasını kaldır
    def remove_domain_certificate(domain : String) : Bool
      @mutex.synchronize do
        if @domain_certs.delete(domain)
          Log.info { "Certificate removed for domain '#{domain}'" }
          true
        else
          false
        end
      end
    end

    # Sertifika yenileme gerekiyor mu kontrol et (dosya tarihi bazlı)
    def needs_renewal?(domain : String, days_before : Int32 = 30) : Bool
      cert = get_certificate(domain)
      return true unless cert

      begin
        cert_mtime = File.info(cert.cert_file).modification_time
        # Dosya 60 günden eski ise yenileme gerekiyor (90 gün Let's Encrypt - 30 gün önceden)
        cert_mtime < Time.utc - (90 - days_before).days
      rescue
        true
      end
    end

    # TLS context'i domain sertifikaları ile yapılandır
    def configure_tls_context(tls_context : OpenSSL::SSL::Context::Server) : Bool
      # Varsayılan sertifikayı yükle
      if default = @default_cert
        begin
          tls_context.certificate_chain = default.cert_file
          tls_context.private_key = default.key_file
          Log.info { "Default TLS certificate configured" }
        rescue ex
          Log.error { "Failed to load default certificate: #{ex.message}" }
          return false
        end
      elsif @domain_certs.size > 0
        # Varsayılan yoksa ilk domain sertifikasını kullan
        first_cert = @domain_certs.values.first
        begin
          tls_context.certificate_chain = first_cert.cert_file
          tls_context.private_key = first_cert.key_file
          Log.info { "Using first domain certificate as default: #{first_cert.domain}" }
        rescue ex
          Log.error { "Failed to load certificate for #{first_cert.domain}: #{ex.message}" }
          return false
        end
      else
        Log.error { "No certificates configured for SNI" }
        return false
      end

      true
    end

    # DomainConfig'lerden sertifikaları yükle
    def load_from_domain_configs(domains : Hash(String, DomainConfig), letsencrypt_manager : LetsEncryptManager? = nil) : Int32
      loaded_count = 0

      domains.each do |domain, config|
        if config.has_custom_cert?
          # Custom sertifika kullan
          if cert_file = config.cert_file
            if key_file = config.key_file
              if add_domain_certificate(domain, cert_file, key_file, false)
                loaded_count += 1
              end
            end
          end
        elsif config.use_letsencrypt? && letsencrypt_manager
          # Let's Encrypt sertifikası al veya oluştur
          cert_path, key_path = letsencrypt_manager.get_or_create_certificate(domain, config.letsencrypt_email)
          if cert_path && key_path
            if add_domain_certificate(domain, cert_path, key_path, true)
              loaded_count += 1
            end
          end
        end
      end

      Log.info { "Loaded #{loaded_count} domain certificates" }
      loaded_count
    end

    # Sertifika dizini al
    def cert_dir : String
      @cert_dir
    end
  end

  # TLS sertifika yönetimi
  class TLSManager
    Log = ::Log.for("tls_manager")

    @cert_file : String?
    @key_file : String?
    @auto_generate : Bool
    @auto_cert_dir : String
    @tls_ciphers : String?

    def initialize(
      cert_file : String? = nil,
      key_file : String? = nil,
      auto_generate : Bool = false,
      auto_cert_dir : String = "config/certs",
      tls_ciphers : String? = nil,
    )
      @cert_file = cert_file
      @key_file = key_file
      @auto_generate = auto_generate
      @auto_cert_dir = auto_cert_dir
      @tls_ciphers = tls_ciphers
    end

    # TLS context oluştur ve döndür
    def get_tls_context : OpenSSL::SSL::Context::Server?
      tls_context = OpenSSL::SSL::Context::Server.new

      # TLS versiyonu OpenSSL'in varsayılan ayarlarına göre belirlenir
      # Crystal'ın OpenSSL binding'i genellikle TLS 1.2 ve üzerini destekler

      # Cipher suite'leri ayarla (eğer belirtilmişse)
      if ciphers = @tls_ciphers
        tls_context.ciphers = ciphers
      end

      # Sertifika ve key yükle
      cert_path : String?
      key_path : String?

      if @auto_generate
        cert_path, key_path = generate_self_signed
      elsif @cert_file && @key_file
        cert_path = @cert_file
        key_path = @key_file
      else
        # Fallback: Sertifika dosyaları yoksa otomatik olarak self-signed oluştur
        Log.warn { "TLS enabled but no certificates provided. Auto-generating self-signed certificate as fallback." }
        cert_path, key_path = generate_self_signed
      end

      # Sertifika ve key dosyalarını yükle
      if cert_path && key_path
        begin
          tls_context.certificate_chain = cert_path
          tls_context.private_key = key_path
          Log.info { "TLS certificates loaded: cert=#{cert_path}, key=#{key_path}" }
        rescue ex
          Log.error { "Failed to load TLS certificates: #{ex.message}" }
          return nil
        end
      end

      tls_context
    end

    # Self-signed sertifika oluştur
    private def generate_self_signed : Tuple(String, String)
      # Dizin yoksa oluştur
      FileUtils.mkdir_p(@auto_cert_dir)

      cert_path = File.join(@auto_cert_dir, "cert.pem")
      key_path = File.join(@auto_cert_dir, "key.pem")

      # Eğer sertifikalar zaten varsa ve yeni ise, yeniden oluşturma
      if File.exists?(cert_path) && File.exists?(key_path)
        begin
          # Dosya tarihini kontrol et (30 günden daha yeni ise kullan)
          cert_mtime = File.info(cert_path).modification_time
          if cert_mtime > Time.utc - 30.days
            Log.info { "Using existing self-signed certificate: #{cert_path}" }
            return {cert_path, key_path}
          end
        rescue
          # Dosya okunamazsa, yeniden oluştur
        end
      end

      Log.info { "Generating self-signed certificate: #{cert_path}" }

      # OpenSSL komut satırı aracını kullanarak self-signed sertifika oluştur
      # Bu yöntem Crystal'ın OpenSSL binding API'sinden daha güvenilir
      openssl_cmd = "openssl"

      # OpenSSL'in mevcut olup olmadığını kontrol et
      unless Process.find_executable(openssl_cmd)
        Log.error { "OpenSSL command not found. Cannot generate self-signed certificate." }
        raise "OpenSSL command not found"
      end

      # Private key oluştur
      key_gen_cmd = [
        openssl_cmd,
        "genrsa",
        "-out", key_path,
        "2048",
      ]

      error_io = IO::Memory.new
      result = Process.run(key_gen_cmd[0], key_gen_cmd[1..], output: Process::Redirect::Close, error: error_io)
      unless result.success?
        error_output = error_io.to_s
        Log.error { "Failed to generate private key: #{error_output}" }
        raise "Failed to generate private key"
      end

      # Self-signed sertifika oluştur
      cert_gen_cmd = [
        openssl_cmd,
        "req",
        "-new",
        "-x509",
        "-key", key_path,
        "-out", cert_path,
        "-days", "365",
        "-subj", "/C=TR/ST=Istanbul/L=Istanbul/O=Kemal WAF/CN=localhost",
        "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1",
      ]

      error_io = IO::Memory.new
      result = Process.run(cert_gen_cmd[0], cert_gen_cmd[1..], output: Process::Redirect::Close, error: error_io)
      unless result.success?
        error_output = error_io.to_s
        Log.error { "Failed to generate certificate: #{error_output}" }
        raise "Failed to generate certificate"
      end

      # Güvenlik: key dosyasına sadece sahibi erişebilsin
      File.chmod(key_path, 0o600)

      Log.info { "Self-signed certificate generated successfully: #{cert_path}" }
      Log.warn { "WARNING: Self-signed certificate is for testing/development only. Do not use in production!" }

      {cert_path, key_path}
    end

    # Sertifika geçerliliğini kontrol et (basit dosya kontrolü)
    def validate_certificate(cert_path : String, key_path : String) : Bool
      return false unless File.exists?(cert_path) && File.exists?(key_path)

      begin
        # Dosyaların okunabilir olduğunu kontrol et
        cert_size = File.size(cert_path)
        key_size = File.size(key_path)

        # Minimum dosya boyutu kontrolü (sertifika ve key dosyaları boş olmamalı)
        if cert_size == 0 || key_size == 0
          Log.warn { "Certificate or key file is empty" }
          return false
        end

        true
      rescue ex
        Log.error { "Certificate validation failed: #{ex.message}" }
        false
      end
    end
  end
end
