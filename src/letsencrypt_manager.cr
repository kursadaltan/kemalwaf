require "http/client"
require "json"
require "file_utils"
require "openssl"

module KemalWAF
  # ACME HTTP-01 Challenge token storage
  class ACMEChallengeStore
    @challenges : Hash(String, String)
    @mutex : Mutex

    def initialize
      @challenges = {} of String => String
      @mutex = Mutex.new
    end

    def set(token : String, key_authorization : String)
      @mutex.synchronize do
        @challenges[token] = key_authorization
      end
    end

    def get(token : String) : String?
      @mutex.synchronize do
        @challenges[token]?
      end
    end

    def delete(token : String)
      @mutex.synchronize do
        @challenges.delete(token)
      end
    end

    def clear
      @mutex.synchronize do
        @challenges.clear
      end
    end
  end

  # Let's Encrypt (ACME) sertifika yönetimi
  # HTTP-01 challenge kullanarak sertifika üretir ve yeniler
  class LetsEncryptManager
    Log = ::Log.for("letsencrypt")

    # Let's Encrypt ACME endpoints
    LETSENCRYPT_STAGING_URL    = "https://acme-staging-v02.api.letsencrypt.org/directory"
    LETSENCRYPT_PRODUCTION_URL = "https://acme-v02.api.letsencrypt.org/directory"

    @cert_dir : String
    @use_staging : Bool
    @challenge_store : ACMEChallengeStore
    @account_key_path : String
    @mutex : Mutex

    getter challenge_store : ACMEChallengeStore

    def initialize(@cert_dir : String = "config/certs/letsencrypt", @use_staging : Bool = false)
      @challenge_store = ACMEChallengeStore.new
      @account_key_path = File.join(@cert_dir, "account.key")
      @mutex = Mutex.new
      FileUtils.mkdir_p(@cert_dir)
    end

    # Domain için sertifika al veya oluştur
    def get_or_create_certificate(domain : String, email : String?) : Tuple(String?, String?)
      cert_path = get_cert_path(domain)
      key_path = get_key_path(domain)

      # Mevcut sertifika varsa ve geçerliyse kullan
      if File.exists?(cert_path) && File.exists?(key_path)
        if !needs_renewal?(domain)
          Log.info { "Using existing Let's Encrypt certificate for '#{domain}'" }
          return {cert_path, key_path}
        end
        Log.info { "Certificate for '#{domain}' needs renewal" }
      end

      # Yeni sertifika oluştur
      if create_certificate(domain, email)
        {cert_path, key_path}
      else
        {nil, nil}
      end
    end

    # Sertifika oluştur (ACME protokolü veya Certbot fallback)
    def create_certificate(domain : String, email : String?) : Bool
      Log.info { "Creating Let's Encrypt certificate for '#{domain}'" }

      # Önce Certbot'u dene (daha güvenilir)
      if certbot_available?
        return create_certificate_with_certbot(domain, email)
      end

      # Certbot yoksa, basit ACME istemcisi kullan
      Log.warn { "Certbot not found, using simplified ACME client" }
      create_certificate_with_acme(domain, email)
    end

    # Certbot ile sertifika oluştur
    private def create_certificate_with_certbot(domain : String, email : String?) : Bool
      Log.info { "Using Certbot to obtain certificate for '#{domain}'" }

      domain_cert_dir = File.join(@cert_dir, domain)
      FileUtils.mkdir_p(domain_cert_dir)

      # Certbot webroot mode için komut oluştur
      # Webroot path'i WAF'ın ACME challenge dosyalarını sunduğu dizin olmalı
      webroot = webroot_path
      FileUtils.mkdir_p(webroot)
      FileUtils.mkdir_p(File.join(webroot, ".well-known", "acme-challenge"))

      # Certbot varsayılan olarak /etc/letsencrypt/live/domain/ altına yazar
      # Biz kendi dizinimize kopyalayacağız
      cmd_args = [
        "certonly",
        "--webroot",
        "-w", webroot,
        "-d", domain,
        "--non-interactive",
        "--agree-tos",
        "--keep-until-expiring", # Mevcut geçerli sertifikayı koru
        "--expand",              # Yeni domain'ler eklendiğinde genişlet
      ]

      if email
        cmd_args << "--email"
        cmd_args << email
      else
        cmd_args << "--register-unsafely-without-email"
      end

      if @use_staging
        cmd_args << "--staging"
      end

      Log.debug { "Running certbot with args: #{cmd_args.join(" ")}" }

      output_io = IO::Memory.new
      error_io = IO::Memory.new
      result = Process.run("certbot", cmd_args, output: output_io, error: error_io)

      if result.success?
        Log.info { "Certbot successfully obtained certificate for '#{domain}'" }

        # Certbot'un oluşturduğu sertifikaları kendi dizinimize kopyala
        letsencrypt_live_dir = "/etc/letsencrypt/live/#{domain}"
        if Dir.exists?(letsencrypt_live_dir)
          copy_letsencrypt_certificates(domain, letsencrypt_live_dir)
        else
          Log.warn { "Certbot succeeded but live directory not found: #{letsencrypt_live_dir}" }
          # Staging modunda farklı bir path olabilir
          staging_dir = "/etc/letsencrypt/live/#{domain}-0001"
          if Dir.exists?(staging_dir)
            copy_letsencrypt_certificates(domain, staging_dir)
          end
        end

        true
      else
        error_output = error_io.to_s
        output_text = output_io.to_s
        Log.error { "Certbot failed for '#{domain}':" }
        Log.error { "  stdout: #{output_text}" } unless output_text.empty?
        Log.error { "  stderr: #{error_output}" } unless error_output.empty?
        false
      end
    end

    # Certbot'un oluşturduğu sertifikaları kendi dizinimize kopyala
    private def copy_letsencrypt_certificates(domain : String, source_dir : String) : Bool
      domain_cert_dir = File.join(@cert_dir, domain)
      FileUtils.mkdir_p(domain_cert_dir)

      begin
        # fullchain.pem -> cert.pem
        source_fullchain = File.join(source_dir, "fullchain.pem")
        if File.exists?(source_fullchain)
          FileUtils.cp(source_fullchain, get_cert_path(domain))
          Log.debug { "Copied fullchain.pem to #{get_cert_path(domain)}" }
        end

        # privkey.pem -> privkey.pem
        source_privkey = File.join(source_dir, "privkey.pem")
        if File.exists?(source_privkey)
          FileUtils.cp(source_privkey, get_key_path(domain))
          File.chmod(get_key_path(domain), 0o600)
          Log.debug { "Copied privkey.pem to #{get_key_path(domain)}" }
        end

        # chain.pem (opsiyonel)
        source_chain = File.join(source_dir, "chain.pem")
        if File.exists?(source_chain)
          FileUtils.cp(source_chain, get_chain_path(domain))
          Log.debug { "Copied chain.pem to #{get_chain_path(domain)}" }
        end

        Log.info { "Certificates copied to #{domain_cert_dir}" }
        true
      rescue ex
        Log.error { "Failed to copy certificates: #{ex.message}" }
        false
      end
    end

    # Basit ACME istemcisi ile sertifika oluştur (Certbot yoksa)
    private def create_certificate_with_acme(domain : String, email : String?) : Bool
      # Not: Bu basit bir implementasyon. Production'da Certbot tercih edilmeli.
      Log.warn { "Simplified ACME client - for production use, install Certbot" }

      domain_cert_dir = File.join(@cert_dir, domain)
      FileUtils.mkdir_p(domain_cert_dir)

      # Private key oluştur
      key_path = get_key_path(domain)
      unless File.exists?(key_path)
        unless generate_private_key(key_path)
          return false
        end
      end

      # CSR (Certificate Signing Request) oluştur
      csr_path = File.join(domain_cert_dir, "csr.pem")
      unless generate_csr(domain, key_path, csr_path)
        return false
      end

      # ACME challenge'ı bekle (HTTP-01)
      Log.info { "Waiting for ACME HTTP-01 challenge for '#{domain}'..." }
      Log.info { "Make sure the WAF is accessible on port 80 for domain '#{domain}'" }

      # Bu basit implementasyonda sadece dosyaları hazırlıyoruz
      # Gerçek ACME protokolü Certbot tarafından yönetilmeli
      Log.warn { "Simplified ACME not fully implemented. Please install Certbot:" }
      Log.warn { "  macOS: brew install certbot" }
      Log.warn { "  Linux: apt-get install certbot / yum install certbot" }

      false
    end

    # Private key oluştur
    private def generate_private_key(key_path : String) : Bool
      openssl_cmd = "openssl"
      unless Process.find_executable(openssl_cmd)
        Log.error { "OpenSSL command not found" }
        return false
      end

      error_io = IO::Memory.new
      result = Process.run(openssl_cmd, ["genrsa", "-out", key_path, "4096"],
        output: Process::Redirect::Close, error: error_io)

      if result.success?
        File.chmod(key_path, 0o600)
        true
      else
        Log.error { "Failed to generate private key: #{error_io.to_s}" }
        false
      end
    end

    # CSR oluştur
    private def generate_csr(domain : String, key_path : String, csr_path : String) : Bool
      openssl_cmd = "openssl"

      error_io = IO::Memory.new
      result = Process.run(openssl_cmd, [
        "req", "-new",
        "-key", key_path,
        "-out", csr_path,
        "-subj", "/CN=#{domain}",
      ], output: Process::Redirect::Close, error: error_io)

      if result.success?
        true
      else
        Log.error { "Failed to generate CSR: #{error_io.to_s}" }
        false
      end
    end

    # Sertifika yenileme gerekiyor mu?
    def needs_renewal?(domain : String, days_before : Int32 = 30) : Bool
      cert_path = get_cert_path(domain)
      return true unless File.exists?(cert_path)

      begin
        # Dosya tarihine göre kontrol (90 gün - days_before)
        cert_mtime = File.info(cert_path).modification_time
        renewal_threshold = Time.utc - (90 - days_before).days
        cert_mtime < renewal_threshold
      rescue
        true
      end
    end

    # Sertifika yenile
    def renew_certificate(domain : String, email : String?) : Bool
      Log.info { "Renewing certificate for '#{domain}'" }

      # Certbot ile yenileme
      if certbot_available?
        error_io = IO::Memory.new
        cmd_args = ["renew", "--cert-name", domain, "--non-interactive"]
        if @use_staging
          cmd_args << "--staging"
        end

        result = Process.run("certbot", cmd_args, output: Process::Redirect::Close, error: error_io)

        if result.success?
          Log.info { "Certificate renewed successfully for '#{domain}'" }
          return true
        else
          Log.warn { "Certbot renew failed, trying to create new certificate" }
        end
      end

      # Yenileme başarısız, yeni sertifika oluştur
      create_certificate(domain, email)
    end

    # Yenileme gereken tüm sertifikaları yenile
    def renew_all_certificates(domains : Array(String), email : String?) : Int32
      renewed = 0
      domains.each do |domain|
        if needs_renewal?(domain)
          if renew_certificate(domain, email)
            renewed += 1
          end
        end
      end
      renewed
    end

    # Certbot mevcut mu?
    def certbot_available? : Bool
      !!Process.find_executable("certbot")
    end

    # Sertifika dosya yolları
    def get_cert_path(domain : String) : String
      File.join(@cert_dir, domain, "cert.pem")
    end

    def get_key_path(domain : String) : String
      File.join(@cert_dir, domain, "privkey.pem")
    end

    def get_fullchain_path(domain : String) : String
      File.join(@cert_dir, domain, "fullchain.pem")
    end

    def get_chain_path(domain : String) : String
      File.join(@cert_dir, domain, "chain.pem")
    end

    # ACME webroot dizini
    def webroot_path : String
      File.join(@cert_dir, "webroot")
    end

    # ACME challenge dosyası yaz (HTTP-01 için)
    def write_challenge_file(token : String, content : String)
      challenge_dir = File.join(webroot_path, ".well-known", "acme-challenge")
      FileUtils.mkdir_p(challenge_dir)
      challenge_file = File.join(challenge_dir, token)
      File.write(challenge_file, content)
      @challenge_store.set(token, content)
      Log.debug { "ACME challenge file written: #{challenge_file}" }
    end

    # ACME challenge dosyası oku
    def read_challenge_file(token : String) : String?
      # Önce memory store'dan oku
      if content = @challenge_store.get(token)
        return content
      end

      # Dosyadan oku
      challenge_file = File.join(webroot_path, ".well-known", "acme-challenge", token)
      if File.exists?(challenge_file)
        File.read(challenge_file)
      else
        nil
      end
    end

    # ACME challenge dosyası sil
    def delete_challenge_file(token : String)
      @challenge_store.delete(token)
      challenge_file = File.join(webroot_path, ".well-known", "acme-challenge", token)
      File.delete(challenge_file) if File.exists?(challenge_file)
    end

    # Staging modunda mı?
    def staging? : Bool
      @use_staging
    end

    # Sertifika dizini
    def cert_dir : String
      @cert_dir
    end
  end
end
