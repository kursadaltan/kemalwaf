require "http"

# WAF helper functions
module WAFHelpers
  # Extract client IP from request headers
  # Priority: X-Forwarded-For (first IP) > X-Real-IP > "unknown"
  def self.extract_client_ip(request : HTTP::Request) : String
    # Get IP from X-Forwarded-For header
    if forwarded_for = request.headers["X-Forwarded-For"]?
      # Get first IP (first real IP in proxy chain)
      forwarded_for.split(',')[0].strip
    elsif real_ip = request.headers["X-Real-IP"]?
      real_ip.strip
    else
      # Remote address (can be obtained from Kemal context)
      "unknown"
    end
  end

  # Extract domain from Host header
  # Removes port if present (e.g., "example.com:8080" -> "example.com")
  def self.extract_domain(request : HTTP::Request) : String?
    host = request.headers["Host"]?
    return nil unless host

    # Remove port (e.g., "example.com:8080" -> "example.com")
    host.split(':')[0].strip.downcase
  end
end


