import { useState, useEffect, useRef } from 'react'
import { FileText, Search, Trash2, Wifi, WifiOff, RefreshCw, Filter, Play, Pause } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { useLogStream, LogEntry } from '@/lib/useLogStream'

interface LogsSettingsProps {
  domain: string
}

type FilterType = 'all' | 'blocked' | 'observed' | 'allowed'

export function LogsSettings({ domain }: LogsSettingsProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [filterType, setFilterType] = useState<FilterType>('all')
  const [autoScroll, setAutoScroll] = useState(true)
  const logsEndRef = useRef<HTMLTableRowElement>(null)

  const { logs, isConnected, error, clearLogs, reconnect, start, stop, isPaused } = useLogStream({
    domain,
    enabled: true,
    maxEntries: 100,
  })

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: 'smooth' })
    }
  }, [logs, autoScroll])

  // Filter logs
  const filteredLogs = logs.filter((log) => {
    // Filter by type
    if (filterType === 'blocked' && !log.blocked) return false
    if (filterType === 'observed' && !log.observed) return false
    if (filterType === 'allowed' && (log.blocked || log.observed)) return false

    // Search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase()
      return (
        log.path?.toLowerCase().includes(query) ||
        log.client_ip?.toLowerCase().includes(query) ||
        log.method?.toLowerCase().includes(query) ||
        log.rule_message?.toLowerCase().includes(query) ||
        log.user_agent?.toLowerCase().includes(query)
      )
    }

    return true
  })

  const formatTimestamp = (timestamp: string) => {
    try {
      const date = new Date(timestamp)
      const now = new Date()
      const diffMs = now.getTime() - date.getTime()
      const diffSecs = Math.floor(diffMs / 1000)
      const diffMins = Math.floor(diffSecs / 60)
      const diffHours = Math.floor(diffMins / 60)
      const diffDays = Math.floor(diffHours / 24)

      if (diffSecs < 60) return `${diffSecs}s ago`
      if (diffMins < 60) return `${diffMins}m ago`
      if (diffHours < 24) return `${diffHours}h ago`
      if (diffDays < 7) return `${diffDays}d ago`
      return date.toLocaleString()
    } catch {
      return timestamp
    }
  }

  const getStatusBadge = (log: LogEntry) => {
    if (log.blocked) {
      return <Badge variant="destructive">Blocked</Badge>
    }
    if (log.observed) {
      return <Badge variant="outline" className="border-yellow-500 text-yellow-500">Observed</Badge>
    }
    return <Badge variant="outline" className="border-green-500 text-green-500">Allowed</Badge>
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="flex items-center gap-2">
                <FileText className="h-5 w-5" />
                WAF Logs - {domain}
              </CardTitle>
              <CardDescription>
                Real-time WAF request logs for this domain
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              {isConnected ? (
                <Badge variant="outline" className="border-green-500 text-green-500">
                  <Wifi className="h-3 w-3 mr-1" />
                  Connected
                </Badge>
              ) : (
                <Badge variant="outline" className="border-red-500 text-red-500">
                  <WifiOff className="h-3 w-3 mr-1" />
                  {isPaused ? 'Paused' : 'Disconnected'}
                </Badge>
              )}
              {isPaused ? (
                <Button variant="outline" size="sm" onClick={start}>
                  <Play className="h-4 w-4 mr-1" />
                  Start
                </Button>
              ) : (
                <Button variant="outline" size="sm" onClick={stop}>
                  <Pause className="h-4 w-4 mr-1" />
                  Pause
                </Button>
              )}
              {error && !isPaused && (
                <Button variant="ghost" size="sm" onClick={reconnect}>
                  <RefreshCw className="h-4 w-4 mr-1" />
                  Reconnect
                </Button>
              )}
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Controls */}
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search logs..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-9"
              />
            </div>
            <Select value={filterType} onValueChange={(v) => setFilterType(v as FilterType)}>
              <SelectTrigger className="w-full sm:w-40">
                <Filter className="h-4 w-4 mr-2" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Logs</SelectItem>
                <SelectItem value="blocked">Blocked</SelectItem>
                <SelectItem value="observed">Observed</SelectItem>
                <SelectItem value="allowed">Allowed</SelectItem>
              </SelectContent>
            </Select>
            <div className="flex items-center gap-2">
              <Label htmlFor="autoScroll" className="text-sm whitespace-nowrap">Auto-scroll</Label>
              <Switch
                id="autoScroll"
                checked={autoScroll}
                onCheckedChange={setAutoScroll}
              />
            </div>
            <Button variant="outline" size="sm" onClick={clearLogs}>
              <Trash2 className="h-4 w-4 mr-1" />
              Clear
            </Button>
          </div>

          {/* Stats */}
          <div className="flex gap-4 text-sm">
            <span className="text-muted-foreground">
              Total: <span className="font-medium">{logs.length}</span>
            </span>
            <span className="text-muted-foreground">
              Filtered: <span className="font-medium">{filteredLogs.length}</span>
            </span>
            <span className="text-muted-foreground">
              Blocked: <span className="text-red-400 font-medium">
                {logs.filter(l => l.blocked).length}
              </span>
            </span>
            <span className="text-muted-foreground">
              Observed: <span className="text-yellow-400 font-medium">
                {logs.filter(l => l.observed).length}
              </span>
            </span>
          </div>

          {/* Logs Table */}
          <div className="border rounded-lg overflow-hidden">
            <div className="max-h-[600px] overflow-y-auto">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 sticky top-0">
                  <tr>
                    <th className="text-left p-2 font-medium">Time</th>
                    <th className="text-left p-2 font-medium">Status</th>
                    <th className="text-left p-2 font-medium">IP</th>
                    <th className="text-left p-2 font-medium">Method</th>
                    <th className="text-left p-2 font-medium">Path</th>
                    <th className="text-left p-2 font-medium">Rule</th>
                    <th className="text-left p-2 font-medium">Duration</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredLogs.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="p-8 text-center text-muted-foreground">
                        {logs.length === 0
                          ? (isConnected ? 'Waiting for logs...' : 'Not connected')
                          : 'No logs match the current filters'}
                      </td>
                    </tr>
                  ) : (
                    filteredLogs.map((log, index) => (
                      <tr
                        key={`${log.request_id}-${index}`}
                        className="border-t hover:bg-muted/30 transition-colors"
                      >
                        <td className="p-2 text-muted-foreground font-mono text-xs">
                          {formatTimestamp(log.timestamp)}
                        </td>
                        <td className="p-2">{getStatusBadge(log)}</td>
                        <td className="p-2 font-mono text-xs">{log.client_ip || 'unknown'}</td>
                        <td className="p-2">
                          <Badge variant="outline" className="text-xs">
                            {log.method || 'N/A'}
                          </Badge>
                        </td>
                        <td className="p-2">
                          <div className="max-w-xs truncate" title={log.path}>
                            {log.path || '/'}
                          </div>
                          {log.query && (
                            <div className="text-xs text-muted-foreground truncate max-w-xs" title={log.query}>
                              ?{log.query}
                            </div>
                          )}
                        </td>
                        <td className="p-2">
                          {log.rule_id ? (
                            <div className="flex flex-col gap-1">
                              <span className="font-mono text-xs">#{log.rule_id}</span>
                              {log.rule_message && (
                                <span className="text-xs text-muted-foreground truncate max-w-xs" title={log.rule_message}>
                                  {log.rule_message}
                                </span>
                              )}
                            </div>
                          ) : (
                            <span className="text-muted-foreground text-xs">-</span>
                          )}
                        </td>
                        <td className="p-2 text-muted-foreground text-xs">
                          {log.duration_ms ? `${log.duration_ms.toFixed(2)}ms` : '-'}
                        </td>
                      </tr>
                    ))
                  )}
                  <tr ref={logsEndRef}>
                    <td colSpan={7} />
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {error && (
            <div className="p-3 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive text-sm">
              Error: {error.message}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
