require "ecr"
require "uuid"

# Constants
WAF_LOGO_URL = "https://avatars3.githubusercontent.com/u/15321198?v=3&s=200"

# WAF error page renderer
module WAFRenderer
  def self.render_403(rule_id : String?, message : String?, observe : Bool) : String
    logo = WAF_LOGO_URL
    rid = rule_id || "N/A"
    msg = message || "Suspicious request detected and blocked."
    mode = observe ? "observe" : "enforce"
    ray = Random::Secure.hex(16)
    timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%SZ")

    ECR.render("#{__DIR__}/views/403.ecr")
  end

  def self.render_502(domain : String, upstream : String, message : String) : String
    logo = WAF_LOGO_URL
    msg = message
    ray = Random::Secure.hex(16)
    timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%SZ")

    ECR.render("#{__DIR__}/views/502.ecr")
  end

  def self.render_429(limit : Int32, reset_at : Time, message : String) : String
    logo = WAF_LOGO_URL
    msg = message
    ray = Random::Secure.hex(16)
    timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%SZ")
    reset_at_str = reset_at.to_s("%Y-%m-%d %H:%M:%S UTC")

    ECR.render("#{__DIR__}/views/429.ecr")
  end
end
