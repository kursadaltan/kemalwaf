// Dynamic API base URL
// Development: direct to backend (localhost:8888)
// Production: relative to current base path
// If base is "/admin/", API will be at "/admin/api"
// If base is "/", API will be at "/api"
const getApiBase = () => {
  if (import.meta.env.DEV) {
    return 'http://localhost:8888/api'
  }
  
  // Get base path from vite config (e.g., "/" or "/admin/")
  const base = import.meta.env.BASE_URL || '/'
  // Ensure base ends with /
  const normalizedBase = base.endsWith('/') ? base : base + '/'
  return `${normalizedBase}api`
}

const API_BASE = getApiBase()

class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
    this.name = 'ApiError'
  }
}

// Token management
const TOKEN_KEY = 'waf_admin_token'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY)
}

async function request<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const url = `${API_BASE}${endpoint}`
  
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }

  // Add existing headers
  if (options.headers) {
    Object.entries(options.headers).forEach(([key, value]) => {
      headers[key] = value as string
    })
  }

  // Add Authorization header if token exists
  const token = getToken()
  if (token) {
    headers['Authorization'] = `Bearer ${token}`
  }
  
  const response = await fetch(url, {
    ...options,
    headers,
  })

  if (!response.ok) {
    if (response.status === 401) {
      clearToken()
    }
    const error = await response.json().catch(() => ({ error: 'Unknown error' }))
    throw new ApiError(response.status, error.error || 'Request failed')
  }

  return response.json()
}

// Types
export interface User {
  id: number
  email: string
  created_at?: string
  last_login?: string
}

export interface SetupStatus {
  setup_required: boolean
  version: string
}

export interface ProxyHost {
  domain: string
  default_upstream: string
  upstream_host_header: string
  preserve_original_host: boolean
  verify_ssl: boolean
  ssl: {
    enabled: boolean
    type: 'letsencrypt' | 'custom' | 'none'
    letsencrypt_email?: string
    cert_file?: string
    key_file?: string
  }
  status: 'online' | 'offline'
}

export interface GlobalConfig {
  mode: 'enforce' | 'observe' | 'disabled'
  rate_limiting: {
    enabled: boolean
    default_limit: number
    window: string
    block_duration: string
  }
  geoip: {
    enabled: boolean
    mmdb_file?: string
    blocked_countries: string[]
    allowed_countries: string[]
  }
  ip_filtering: {
    enabled: boolean
    whitelist_file?: string
    blacklist_file?: string
  }
  server: {
    http_enabled: boolean
    https_enabled: boolean
    http_port: number
    https_port: number
  }
}

export interface Stats {
  hosts: {
    total: number
    ssl_enabled: number
  }
  requests: {
    total: number
    blocked: number
    allowed: number
  }
  performance: {
    requests_per_second: number
    avg_response_time_ms: number
  }
  uptime_seconds: number
  waf_available: boolean
}

export interface CreateHostData {
  domain: string
  upstream_url: string
  upstream_host_header?: string
  preserve_host?: boolean
  verify_ssl?: boolean
  ssl_type?: 'letsencrypt' | 'custom' | 'none'
  ssl_email?: string
  cert_file?: string
  key_file?: string
}

// WAF Rule Types
export interface VariableSpec {
  type: string
  names?: string[]
}

export interface Rule {
  id: number
  name?: string
  msg: string
  pattern?: string
  action: string
  operator?: string
  severity?: string
  category?: string
  paranoia_level?: number
  tags?: string[]
  transforms?: string[]
  variables?: VariableSpec[]
  score?: number
  default_score: number
  source_file?: string
}

export interface RulesResponse {
  rules: Rule[]
  total: number
  categories: string[]
}

export interface RuleFilesResponse {
  files: Array<{
    file: string
    count: number
    rules: number[]
  }>
}

export interface DomainRulesConfig {
  domain: string
  threshold: number
  enabled_rules: number[]
  disabled_rules: number[]
  all_rules: Array<{
    id: number
    name: string
    category?: string
    score: number
  }>
}

export interface CreateRuleData {
  id: number
  name?: string
  msg: string
  pattern?: string
  action: string
  operator?: string
  severity?: string
  category?: string
  paranoia_level?: number
  tags?: string[]
  transforms?: string[]
  variables?: VariableSpec[]
  score?: number
  default_score?: number
  target_file?: string
}

export interface UpdateDomainRulesData {
  threshold?: number
  enabled_rules?: number[]
  disabled_rules?: number[]
}

// API functions
export const api = {
  // Auth
  getSetupStatus: () => request<SetupStatus>('/setup/status'),
  
  setup: async (email: string, password: string) => {
    const response = await request<{ success: boolean; message: string; token?: string }>('/setup', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
    // Store token if provided
    if (response.token) {
      setToken(response.token)
    }
    return response
  },

  login: async (email: string, password: string) => {
    const response = await request<{ success: boolean; user: User; token?: string }>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
    // Store token if provided
    if (response.token) {
      setToken(response.token)
    }
    return response
  },

  logout: async () => {
    const response = await request<{ success: boolean }>('/auth/logout', { method: 'POST' })
    clearToken()
    return response
  },

  getMe: () => request<User>('/auth/me'),

  // Hosts
  getHosts: () => request<{ hosts: ProxyHost[] }>('/hosts'),
  
  getHost: (domain: string) =>
    request<ProxyHost>(`/hosts/${encodeURIComponent(domain)}`),

  createHost: (data: CreateHostData) =>
    request<{ success: boolean; message: string; domain: string }>('/hosts', {
      method: 'POST',
      body: JSON.stringify(data),
    }),

  updateHost: (domain: string, data: CreateHostData) =>
    request<{ success: boolean; message: string }>(
      `/hosts/${encodeURIComponent(domain)}`,
      {
        method: 'PUT',
        body: JSON.stringify(data),
      }
    ),

  deleteHost: (domain: string) =>
    request<{ success: boolean; message: string }>(
      `/hosts/${encodeURIComponent(domain)}`,
      { method: 'DELETE' }
    ),

  // Config
  getConfig: () => request<GlobalConfig>('/config'),
  
  updateConfig: (data: Partial<GlobalConfig>) =>
    request<{ success: boolean; message: string }>('/config', {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  reloadConfig: () =>
    request<{ success: boolean; message: string }>('/config/reload', {
      method: 'POST',
    }),

  // IP Lists
  getIPWhitelist: () => request<{ ips: string[] }>('/config/ip-whitelist'),
  
  updateIPWhitelist: (ips: string[]) =>
    request<{ success: boolean }>('/config/ip-whitelist', {
      method: 'PUT',
      body: JSON.stringify({ ips }),
    }),

  getIPBlacklist: () => request<{ ips: string[] }>('/config/ip-blacklist'),
  
  updateIPBlacklist: (ips: string[]) =>
    request<{ success: boolean }>('/config/ip-blacklist', {
      method: 'PUT',
      body: JSON.stringify({ ips }),
    }),

  // Stats & Metrics
  getStats: () => request<Stats>('/stats'),
  
  getMetrics: () => request<Record<string, unknown>>('/metrics'),

  // WAF Rules
  getRules: (category?: string, severity?: string) => {
    const params = new URLSearchParams()
    if (category) params.append('category', category)
    if (severity) params.append('severity', severity)
    const query = params.toString()
    return request<RulesResponse>(`/rules${query ? `?${query}` : ''}`)
  },

  getRule: (id: number) => request<Rule>(`/rules/${id}`),

  createRule: (data: CreateRuleData) =>
    request<{ success: boolean; message: string; id: number }>('/rules', {
      method: 'POST',
      body: JSON.stringify(data),
    }),

  updateRule: (id: number, data: Partial<CreateRuleData>) =>
    request<{ success: boolean; message: string }>(`/rules/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  deleteRule: (id: number) =>
    request<{ success: boolean; message: string }>(`/rules/${id}`, {
      method: 'DELETE',
    }),

  reloadRules: () =>
    request<{ success: boolean; message: string; count: number }>('/rules/reload', {
      method: 'POST',
    }),

  getRuleFiles: () => request<RuleFilesResponse>('/rules/files'),

  // Domain WAF Configuration
  getDomainRules: (domain: string) =>
    request<DomainRulesConfig>(`/rules/domains/${encodeURIComponent(domain)}`),

  updateDomainRules: (domain: string, data: UpdateDomainRulesData) =>
    request<{ success: boolean; message: string }>(
      `/rules/domains/${encodeURIComponent(domain)}`,
      {
        method: 'PUT',
        body: JSON.stringify(data),
      }
    ),

  getDomainThreshold: (domain: string) =>
    request<{ domain: string; threshold: number }>(
      `/rules/domains/${encodeURIComponent(domain)}/threshold`
    ),

  updateDomainThreshold: (domain: string, threshold: number) =>
    request<{ success: boolean; message: string }>(
      `/rules/domains/${encodeURIComponent(domain)}/threshold`,
      {
        method: 'PUT',
        body: JSON.stringify({ threshold }),
      }
    ),

  // Audit Logs
  getAuditLogs: (limit: number = 100, offset: number = 0) =>
    request<{ logs: Array<{ id: number; user_id: number; action: string; details: string | null; ip_address: string | null; created_at: string }> }>(
      `/config/audit-logs?limit=${limit}&offset=${offset}`
    ),

  // Domain Logs
  getDomainLogs: (domain: string, limit: number = 100, offset: number = 0) =>
    request<{ logs: Array<Record<string, unknown>>; total: number; has_more: boolean }>(
      `/logs/domains/${encodeURIComponent(domain)}?limit=${limit}&offset=${offset}`
    ),

  getDomainLogFiles: (domain: string) =>
    request<{ files: Array<{ date: string; size: number; path: string }> }>(
      `/logs/domains/${encodeURIComponent(domain)}/files`
    ),

  // Domain Custom Rules
  getDomainCustomRules: (domain: string) =>
    request<{ rules: Rule[]; total: number }>(
      `/rules/domains/${encodeURIComponent(domain)}/custom`
    ),

  getDomainCustomRule: (domain: string, id: number) =>
    request<Rule>(
      `/rules/domains/${encodeURIComponent(domain)}/custom/${id}`
    ),

  createDomainCustomRule: (domain: string, rule: Partial<Rule> & { id: number; msg: string; action: string }) =>
    request<{ success: boolean; message: string; id: number }>(
      `/rules/domains/${encodeURIComponent(domain)}/custom`,
      {
        method: 'POST',
        body: JSON.stringify(rule),
      }
    ),

  updateDomainCustomRule: (domain: string, id: number, rule: Partial<Rule>) =>
    request<{ success: boolean; message: string }>(
      `/rules/domains/${encodeURIComponent(domain)}/custom/${id}`,
      {
        method: 'PUT',
        body: JSON.stringify(rule),
      }
    ),

  deleteDomainCustomRule: (domain: string, id: number) =>
    request<{ success: boolean; message: string }>(
      `/rules/domains/${encodeURIComponent(domain)}/custom/${id}`,
      {
        method: 'DELETE',
      }
    ),
}

export { ApiError }

