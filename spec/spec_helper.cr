require "spec"
require "json"

# Test ortamında WAF server'ı başlatmamak için sadece modülleri require et
require "../src/rule_loader"
require "../src/evaluator"
require "../src/proxy_client"
require "../src/metrics"
require "../src/rate_limiter"
require "../src/ip_filter"
require "../src/connection_pool"
require "../src/connection_pool_manager"
require "../src/config_loader"

# Test helper ve setup
Spec.before_each do
  # Her test öncesi temizlik yapılabilir
end

Spec.after_each do
  # Her test sonrası temizlik yapılabilir
end
