const API_BASE = import.meta.env.DEV ? 'http://localhost:8888/api' : '/api'

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
}

export { ApiError }

