require "http"
require "uri"
require "./rule_loader"
require "./libinjection"

module KemalWAF
  # İstek değerlendirme sonucu
  struct EvaluationResult
    property blocked : Bool
    property observed : Bool
    property rule_id : Int32?
    property message : String?
    property matched_variable : String?
    property matched_value : String?

    def initialize(@blocked, @rule_id = nil, @message = nil, @observed = false, @matched_variable = nil, @matched_value = nil)
    end
  end

  # İstek değerlendirici
  class Evaluator
    Log = ::Log.for("evaluator")

    @rule_loader : RuleLoader
    @observe_mode : Bool
    @body_limit : Int32

    def initialize(@rule_loader : RuleLoader, @observe_mode : Bool, @body_limit : Int32)
    end

    def evaluate(request : HTTP::Request, body : String?) : EvaluationResult
      # Değişken snapshot'ı oluştur
      variables = build_variable_snapshot(request, body)

      # Her kuralı değerlendir
      @rule_loader.rules.each do |rule|
        match_result = match_rule?(rule, variables)
        if match_result
          matched_var, matched_val = match_result
          Log.info { "Kural eşleşmesi: ID=#{rule.id}, Msg=#{rule.msg}" }

          if rule.action == "deny"
            if @observe_mode
              Log.warn { "[OBSERVE MODE] Kural #{rule.id} eşleşti ama engellenmedi" }
              return EvaluationResult.new(
                blocked: false,
                rule_id: rule.id,
                message: rule.msg,
                observed: true,
                matched_variable: matched_var,
                matched_value: matched_val
              )
            else
              Log.warn { "İstek engellendi: Kural #{rule.id}" }
              return EvaluationResult.new(
                blocked: true,
                rule_id: rule.id,
                message: rule.msg,
                matched_variable: matched_var,
                matched_value: matched_val
              )
            end
          end
        end
      end

      EvaluationResult.new(blocked: false)
    end

    private def build_variable_snapshot(request : HTTP::Request, body : String?) : Hash(String, Array(String))
      snapshot = Hash(String, Array(String)).new

      # REQUEST_LINE: METHOD PATH PROTOCOL
      request_line = "#{request.method} #{request.resource} HTTP/#{request.version}"
      snapshot["REQUEST_LINE"] = [request_line]

      # REQUEST_FILENAME: Request path
      snapshot["REQUEST_FILENAME"] = [request.resource]

      # REQUEST_BASENAME: Basename of request path
      basename = File.basename(request.resource)
      snapshot["REQUEST_BASENAME"] = [basename]

      # ARGS: Query string parametreleri
      args = [] of String
      args_names = [] of String
      if query = request.query
        URI::Params.parse(query).each do |key, value|
          args << "#{key}=#{value}"
          args_names << key
        end
      end
      snapshot["ARGS"] = args
      snapshot["ARGS_NAMES"] = args_names

      # HEADERS: Tüm başlıklar
      headers = [] of String
      request.headers.each do |key, values|
        values.each do |value|
          headers << "#{key}: #{value}"
        end
      end
      snapshot["HEADERS"] = headers

      # COOKIE: Cookie başlığı ve isimleri
      cookies = [] of String
      cookie_names = [] of String
      if cookie_header = request.headers["Cookie"]?
        cookies << cookie_header
        # Cookie isimlerini parse et
        cookie_header.split(';').each do |cookie|
          if eq_pos = cookie.index('=')
            cookie_names << cookie[0...eq_pos].strip
          end
        end
      end
      snapshot["COOKIE"] = cookies
      snapshot["COOKIE_NAMES"] = cookie_names

      # BODY: İstek gövdesi (limit dahilinde)
      body_values = [] of String
      if body && !body.empty?
        limited_body = body[0...@body_limit]
        if limited_body.size < body.size
          Log.warn { "Body boyutu limiti aşıldı, ilk #{@body_limit} byte okundu" }
        end
        body_values << limited_body
      end
      snapshot["BODY"] = body_values

      snapshot
    end

    private def match_rule?(rule : Rule, variables : Hash(String, Array(String))) : Tuple(String, String)?
      operator = rule.operator || "regex"

      # Variable spec'leri kullan (eğer varsa)
      variable_specs = rule.variable_specs

      variable_specs.each do |spec|
        var_name = spec.type
        var_values = get_variable_values(var_name, spec.names, variables)

        var_values.each do |value|
          # Dönüşümleri uygula
          transformed = apply_transforms(value, rule.transforms)

          # Operator'a göre eşleşme kontrolü
          matched = case operator
                    when "regex"
                      match_regex(rule, transformed)
                    when "libinjection_sqli"
                      LibInjectionWrapper.detect_sqli(transformed)
                    when "libinjection_xss"
                      LibInjectionWrapper.detect_xss(transformed)
                    when "contains"
                      match_contains(rule, transformed)
                    when "starts_with"
                      match_starts_with(rule, transformed)
                    else
                      # Backward compatibility: default regex
                      match_regex(rule, transformed)
                    end

          if matched
            Log.debug { "Eşleşme bulundu: var=#{var_name}, operator=#{operator}" }
            return {var_name, value}
          end
        end
      end

      nil
    end

    private def get_variable_values(var_name : String, header_names : Array(String)?, variables : Hash(String, Array(String))) : Array(String)
      case var_name
      when "HEADERS"
        if header_names && !header_names.empty?
          # Belirli header isimleri için filtrele
          result = [] of String
          if headers = variables["HEADERS"]?
            headers.each do |header|
              header_names.each do |name|
                if header.downcase.starts_with?("#{name.downcase}:")
                  result << header
                end
              end
            end
          end
          result
        else
          variables[var_name]? || [] of String
        end
      else
        variables[var_name]? || [] of String
      end
    end

    private def match_regex(rule : Rule, value : String) : Bool
      return false unless rule.compiled_regex
      rule.compiled_regex.not_nil!.matches?(value)
    end

    private def match_contains(rule : Rule, value : String) : Bool
      return false unless rule.pattern
      value.includes?(rule.pattern.not_nil!)
    end

    private def match_starts_with(rule : Rule, value : String) : Bool
      return false unless rule.pattern
      value.starts_with?(rule.pattern.not_nil!)
    end

    private def apply_transforms(value : String, transforms : Array(String)?) : String
      return value unless transforms

      result = value
      transforms.each do |transform|
        case transform
        when "none"
          # Transform yok, değişiklik yapma
          next
        when "url_decode"
          result = url_decode(result)
        when "url_decode_uni"
          result = url_decode_uni(result)
        when "lowercase"
          result = result.downcase
        when "utf8_to_unicode"
          result = utf8_to_unicode(result)
        when "remove_nulls"
          result = remove_nulls(result)
        when "replace_comments"
          result = replace_comments(result)
        else
          Log.warn { "Bilinmeyen dönüşüm: #{transform}" }
        end
      end
      result
    end

    private def url_decode(value : String) : String
      URI.decode_www_form(value)
    rescue
      value
    end

    private def url_decode_uni(value : String) : String
      # Unicode-aware URL decode (basit implementasyon)
      # Gerçek implementasyon daha karmaşık olabilir
      URI.decode_www_form(value)
    rescue
      value
    end

    private def utf8_to_unicode(value : String) : String
      # UTF-8 to Unicode conversion (basit implementasyon)
      # Crystal zaten UTF-8 kullanıyor, bu transform genelde gerekli değil
      value
    end

    private def remove_nulls(value : String) : String
      value.gsub('\0', "")
    end

    private def replace_comments(value : String) : String
      # SQL ve script comment'lerini kaldır
      result = value
      # SQL comments: -- ve /* */
      result = result.gsub(/--.*$/, "")
      result = result.gsub(/\/\*.*?\*\//, "")
      # HTML comments: <!-- -->
      result = result.gsub(/<!--.*?-->/, "")
      result
    end
  end
end
