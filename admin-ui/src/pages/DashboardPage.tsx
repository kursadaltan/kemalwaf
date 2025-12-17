import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { 
  Shield, 
  Globe, 
  Lock, 
  Zap, 
  Ban, 
  Plus, 
  Search,
  Settings,
  LogOut,
  RefreshCw,
  ChevronDown,
  ExternalLink,
  Trash2,
  Edit,
  MoreVertical,
  FileText
} from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { 
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { api, ProxyHost } from '@/lib/api'
import { formatNumber, formatUptime } from '@/lib/utils'
import { ProxyHostModal } from '@/components/ProxyHostModal'
import { GlobalSettingsModal } from '@/components/GlobalSettingsModal'
import { RulesPage } from '@/pages/RulesPage'

interface StatsCardProps {
  icon: React.ReactNode
  label: string
  value: string | number
  subValue?: string
  trend?: 'up' | 'down' | 'neutral'
}

function StatsCard({ icon, label, value, subValue }: StatsCardProps) {
  return (
    <Card className="card-hover">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <p className="text-sm text-muted-foreground">{label}</p>
            <p className="text-2xl font-bold">{value}</p>
            {subValue && (
              <p className="text-xs text-muted-foreground">{subValue}</p>
            )}
          </div>
          <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center text-primary">
            {icon}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

interface ProxyHostCardProps {
  host: ProxyHost
  onEdit: () => void
  onDelete: () => void
}

function ProxyHostCard({ host, onEdit, onDelete }: ProxyHostCardProps) {
  const [isOpen, setIsOpen] = useState(false)

  return (
    <Collapsible open={isOpen} onOpenChange={setIsOpen}>
      <Card className="card-hover overflow-hidden">
        <CollapsibleTrigger asChild>
          <div className="p-4 cursor-pointer hover:bg-accent/50 transition-colors">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center">
                  <Globe className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="font-semibold">{host.domain}</h3>
                    <Badge variant={host.status === 'online' ? 'success' : 'destructive'} className="text-xs">
                      {host.status}
                    </Badge>
                  </div>
                  <p className="text-sm text-muted-foreground flex items-center gap-1">
                    <span className="font-mono">{host.default_upstream}</span>
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                {host.ssl.enabled && (
                  <Badge variant="outline" className="text-green-400 border-green-400/30">
                    <Lock className="h-3 w-3 mr-1" />
                    {host.ssl.type === 'letsencrypt' ? "Let's Encrypt" : 'SSL'}
                  </Badge>
                )}
                <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${isOpen ? 'rotate-180' : ''}`} />
              </div>
            </div>
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <Separator />
          <div className="p-4 bg-muted/30 space-y-4">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <p className="text-muted-foreground">Upstream</p>
                <p className="font-mono text-xs break-all">{host.default_upstream}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Host Header</p>
                <p className="font-mono text-xs">{host.upstream_host_header || host.domain}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Preserve Host</p>
                <p>{host.preserve_original_host ? 'Yes' : 'No'}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Verify SSL</p>
                <p>{host.verify_ssl ? 'Yes' : 'No'}</p>
              </div>
            </div>
            
            {host.ssl.enabled && (
              <div className="p-3 rounded-lg bg-green-500/10 border border-green-500/20">
                <div className="flex items-center gap-2">
                  <Lock className="h-4 w-4 text-green-400" />
                  <span className="text-sm font-medium text-green-400">
                    SSL/TLS: {host.ssl.type === 'letsencrypt' ? "Let's Encrypt" : 'Custom Certificate'}
                  </span>
                </div>
                {host.ssl.letsencrypt_email && (
                  <p className="text-xs text-muted-foreground mt-1 ml-6">
                    Email: {host.ssl.letsencrypt_email}
                  </p>
                )}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => window.open(`https://${host.domain}`, '_blank')}
              >
                <ExternalLink className="h-4 w-4 mr-1" />
                Open
              </Button>
              <Button variant="outline" size="sm" onClick={onEdit}>
                <Edit className="h-4 w-4 mr-1" />
                Edit
              </Button>
              <Button variant="destructive" size="sm" onClick={onDelete}>
                <Trash2 className="h-4 w-4 mr-1" />
                Delete
              </Button>
            </div>
          </div>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  )
}

export function DashboardPage() {
  const queryClient = useQueryClient()
  const [searchQuery, setSearchQuery] = useState('')
  const [isHostModalOpen, setIsHostModalOpen] = useState(false)
  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false)
  const [editingHost, setEditingHost] = useState<ProxyHost | null>(null)
  const [showRulesPage, setShowRulesPage] = useState(false)

  // Fetch data
  const { data: stats } = useQuery({
    queryKey: ['stats'],
    queryFn: api.getStats,
    refetchInterval: 5000,
  })

  const { data: hostsData, isLoading: isLoadingHosts } = useQuery({
    queryKey: ['hosts'],
    queryFn: api.getHosts,
  })

  const { data: user } = useQuery({
    queryKey: ['me'],
    queryFn: api.getMe,
  })

  const logoutMutation = useMutation({
    mutationFn: api.logout,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['me'] })
      toast.success('Logged out')
    },
  })

  const deleteHostMutation = useMutation({
    mutationFn: api.deleteHost,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hosts'] })
      toast.success('Host deleted')
    },
    onError: () => {
      toast.error('Failed to delete host')
    },
  })

  const reloadConfigMutation = useMutation({
    mutationFn: api.reloadConfig,
    onSuccess: (data) => {
      toast.success(data.message)
    },
    onError: () => {
      toast.error('Failed to reload config')
    },
  })

  const hosts = hostsData?.hosts || []
  const filteredHosts = hosts.filter(host =>
    host.domain.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const handleEdit = (host: ProxyHost) => {
    setEditingHost(host)
    setIsHostModalOpen(true)
  }

  const handleDelete = (domain: string) => {
    if (confirm(`Are you sure you want to delete ${domain}?`)) {
      deleteHostMutation.mutate(domain)
    }
  }

  const handleModalClose = () => {
    setIsHostModalOpen(false)
    setEditingHost(null)
  }

  // Show Rules Page when toggled
  if (showRulesPage) {
    return <RulesPage onBack={() => setShowRulesPage(false)} />
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b bg-card/50 backdrop-blur-sm sticky top-0 z-50">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-9 w-9 rounded-lg bg-primary flex items-center justify-center">
              <Shield className="h-5 w-5 text-primary-foreground" />
            </div>
            <div>
              <h1 className="font-bold text-lg">Kemal WAF</h1>
              <p className="text-xs text-muted-foreground">Admin Panel</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowRulesPage(true)}
            >
              <FileText className="h-4 w-4 mr-1" />
              Global Rules
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => reloadConfigMutation.mutate()}
              disabled={reloadConfigMutation.isPending}
            >
              <RefreshCw className={`h-4 w-4 mr-1 ${reloadConfigMutation.isPending ? 'animate-spin' : ''}`} />
              Reload
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setIsSettingsModalOpen(true)}
            >
              <Settings className="h-4 w-4 mr-1" />
              Settings
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="sm">
                  <span className="max-w-[150px] truncate">{user?.email}</span>
                  <MoreVertical className="h-4 w-4 ml-1" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem disabled>
                  <span className="text-muted-foreground">{user?.email}</span>
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => logoutMutation.mutate()}>
                  <LogOut className="h-4 w-4 mr-2" />
                  Logout
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatsCard
            icon={<Globe className="h-5 w-5" />}
            label="Proxy Hosts"
            value={stats?.hosts.total ?? hosts.length}
            subValue={`${stats?.hosts.ssl_enabled ?? 0} with SSL`}
          />
          <StatsCard
            icon={<Lock className="h-5 w-5" />}
            label="SSL Enabled"
            value={`${stats?.hosts.ssl_enabled ?? 0}/${stats?.hosts.total ?? hosts.length}`}
          />
          <StatsCard
            icon={<Zap className="h-5 w-5" />}
            label="Requests"
            value={formatNumber(stats?.requests.total ?? 0)}
            subValue={stats?.waf_available ? `${stats?.performance.requests_per_second?.toFixed(1) ?? 0}/s` : 'WAF offline'}
          />
          <StatsCard
            icon={<Ban className="h-5 w-5" />}
            label="Blocked"
            value={formatNumber(stats?.requests.blocked ?? 0)}
            subValue={stats?.uptime_seconds ? `Uptime: ${formatUptime(stats.uptime_seconds)}` : undefined}
          />
        </div>

        {/* Proxy Hosts Section */}
        <div className="space-y-4">
          <div className="flex flex-col sm:flex-row gap-4 justify-between">
            <h2 className="text-xl font-bold flex items-center gap-2">
              <Globe className="h-5 w-5 text-primary" />
              Proxy Hosts
            </h2>
            <div className="flex gap-2">
              <div className="relative flex-1 sm:w-64">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search domains..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-9"
                />
              </div>
              <Button onClick={() => setIsHostModalOpen(true)}>
                <Plus className="h-4 w-4 mr-1" />
                Add Host
              </Button>
            </div>
          </div>

          {isLoadingHosts ? (
            <div className="text-center py-12 text-muted-foreground">
              Loading hosts...
            </div>
          ) : filteredHosts.length === 0 ? (
            <Card className="p-12 text-center">
              <Globe className="h-12 w-12 mx-auto text-muted-foreground/50 mb-4" />
              <h3 className="text-lg font-semibold mb-2">
                {searchQuery ? 'No hosts found' : 'No proxy hosts yet'}
              </h3>
              <p className="text-muted-foreground mb-4">
                {searchQuery
                  ? 'Try a different search term'
                  : 'Add your first proxy host to get started'}
              </p>
              {!searchQuery && (
                <Button onClick={() => setIsHostModalOpen(true)}>
                  <Plus className="h-4 w-4 mr-1" />
                  Add Proxy Host
                </Button>
              )}
            </Card>
          ) : (
            <div className="space-y-3">
              {filteredHosts.map((host) => (
                <ProxyHostCard
                  key={host.domain}
                  host={host}
                  onEdit={() => handleEdit(host)}
                  onDelete={() => handleDelete(host.domain)}
                />
              ))}
            </div>
          )}
        </div>
      </main>

      {/* Modals */}
      <ProxyHostModal
        isOpen={isHostModalOpen}
        onClose={handleModalClose}
        host={editingHost}
      />
      <GlobalSettingsModal
        isOpen={isSettingsModalOpen}
        onClose={() => setIsSettingsModalOpen(false)}
      />
    </div>
  )
}

