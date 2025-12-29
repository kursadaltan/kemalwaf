import { useState, useEffect, useRef, useCallback } from 'react'
import { getToken } from './api'

export interface LogEntry {
  timestamp: string
  event_type: string
  request_id?: string
  client_ip?: string
  method?: string
  path?: string
  query?: string
  user_agent?: string
  blocked?: boolean
  observed?: boolean
  rule_id?: number | null
  rule_message?: string | null
  duration_ms?: number
  status_code?: number
  domain?: string
  [key: string]: unknown
}

interface UseLogStreamOptions {
  domain: string
  enabled?: boolean
  maxEntries?: number
  onError?: (error: Error) => void
}

interface UseLogStreamReturn {
  logs: LogEntry[]
  isConnected: boolean
  error: Error | null
  clearLogs: () => void
  reconnect: () => void
  start: () => void
  stop: () => void
  isPaused: boolean
}

export function useLogStream({
  domain,
  enabled = true,
  maxEntries = 100,
  onError,
}: UseLogStreamOptions): UseLogStreamReturn {
  const [logs, setLogs] = useState<LogEntry[]>([])
  const [isConnected, setIsConnected] = useState(false)
  const [error, setError] = useState<Error | null>(null)
  const [isPaused, setIsPaused] = useState(false)
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimeoutRef = useRef<number | null>(null)
  const reconnectAttemptsRef = useRef(0)
  const maxReconnectAttempts = 5
  const baseReconnectDelay = 1000 // 1 second
  const isPausedRef = useRef(false)

  const clearLogs = useCallback(() => {
    setLogs([])
  }, [])

  const connect = useCallback(() => {
    if (!enabled || !domain || isPausedRef.current) return

    // Close existing connection
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }

    try {
      const token = getToken()
      if (!token) {
        const err = new Error('No authentication token')
        setError(err)
        onError?.(err)
        return
      }

      // Determine WebSocket URL (same logic as API base URL)
      let wsUrl: string
      if (import.meta.env.DEV) {
        wsUrl = `ws://localhost:8888/api/logs/domains/${encodeURIComponent(domain)}/stream`
      } else {
        const base = import.meta.env.BASE_URL || '/'
        const normalizedBase = base.endsWith('/') ? base : base + '/'
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
        wsUrl = `${protocol}//${window.location.host}${normalizedBase}api/logs/domains/${encodeURIComponent(domain)}/stream`
      }

      // WebSocket automatically sends cookies, so we don't need to pass token explicitly
      const ws = new WebSocket(wsUrl)

      ws.onopen = () => {
        setIsConnected(true)
        setError(null)
        reconnectAttemptsRef.current = 0
        if (reconnectTimeoutRef.current) {
          clearTimeout(reconnectTimeoutRef.current)
          reconnectTimeoutRef.current = null
        }
      }

      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data)
          if (message.type === 'log_entry' && message.data) {
            const logEntry = message.data as LogEntry
            setLogs((prev) => {
              // Circular buffer: add new entry at the beginning, keep max entries
              const newLogs = [logEntry, ...prev]
              return newLogs.slice(0, maxEntries)
            })
          }
        } catch (err) {
          console.error('Error parsing log message:', err)
        }
      }

      ws.onerror = () => {
        const err = new Error('WebSocket error')
        setError(err)
        onError?.(err)
        setIsConnected(false)
      }

      ws.onclose = () => {
        setIsConnected(false)
        wsRef.current = null

        // Attempt to reconnect if enabled, not paused, and not manually closed
        if (enabled && !isPausedRef.current && reconnectAttemptsRef.current < maxReconnectAttempts) {
          const delay = baseReconnectDelay * Math.pow(2, reconnectAttemptsRef.current) // Exponential backoff
          reconnectAttemptsRef.current++
          reconnectTimeoutRef.current = window.setTimeout(() => {
            connect()
          }, delay)
        } else if (reconnectAttemptsRef.current >= maxReconnectAttempts) {
          const err = new Error('Max reconnection attempts reached')
          setError(err)
          onError?.(err)
        }
      }

      wsRef.current = ws
    } catch (err) {
      const error = err instanceof Error ? err : new Error('Failed to create WebSocket connection')
      setError(error)
      onError?.(error)
      setIsConnected(false)
    }
  }, [domain, enabled, maxEntries, onError])

  const reconnect = useCallback(() => {
    reconnectAttemptsRef.current = 0
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current)
      reconnectTimeoutRef.current = null
    }
    connect()
  }, [connect])

  const stop = useCallback(() => {
    setIsPaused(true)
    isPausedRef.current = true
    
    // Close WebSocket connection
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }
    
    // Clear reconnect timeout
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current)
      reconnectTimeoutRef.current = null
    }
    
    setIsConnected(false)
  }, [])

  const start = useCallback(() => {
    setIsPaused(false)
    isPausedRef.current = false
    reconnectAttemptsRef.current = 0
    connect()
  }, [connect])

  useEffect(() => {
    if (enabled && domain && !isPausedRef.current) {
      connect()
    }

    return () => {
      if (wsRef.current) {
        wsRef.current.close()
        wsRef.current = null
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current)
        reconnectTimeoutRef.current = null
      }
    }
  }, [enabled, domain, connect])

  return {
    logs,
    isConnected,
    error,
    clearLogs,
    reconnect,
    start,
    stop,
    isPaused,
  }
}
