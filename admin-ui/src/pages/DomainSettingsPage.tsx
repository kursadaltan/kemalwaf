import { useParams, useNavigate, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { 
  Shield, 
  Globe, 
  Lock, 
  Zap, 
  Ban, 
  FileText,
  Settings,
  MoreVertical,
  ArrowLeft,
  Loader2
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { api } from '@/lib/api'
import { GeneralSettings } from '@/components/domain-settings/GeneralSettings'
import { SSLSettings } from '@/components/domain-settings/SSLSettings'
import { WAFSettings } from '@/components/domain-settings/WAFSettings'
import { RateLimitingSettings } from '@/components/domain-settings/RateLimitingSettings'
import { IPFilteringSettings } from '@/components/domain-settings/IPFilteringSettings'
import { LogsSettings } from '@/components/domain-settings/LogsSettings'
import { AdvancedSettings } from '@/components/domain-settings/AdvancedSettings'

type MenuItemId = 'general' | 'ssl' | 'waf' | 'rate-limiting' | 'ip-filtering' | 'logs' | 'advanced'

interface MenuItem {
  id: MenuItemId
  label: string
  icon: React.ComponentType<{ className?: string }>
}

const menuItems: MenuItem[] = [
  { id: 'general', label: 'General', icon: Settings },
  { id: 'ssl', label: 'SSL/TLS', icon: Lock },
  { id: 'waf', label: 'WAF Rules', icon: Shield },
  { id: 'rate-limiting', label: 'Rate Limiting', icon: Zap },
  { id: 'ip-filtering', label: 'IP Filtering', icon: Ban },
  { id: 'logs', label: 'Logs & Analytics', icon: FileText },
  { id: 'advanced', label: 'Advanced', icon: MoreVertical },
]

export function DomainSettingsPage() {
  const { domain } = useParams<{ domain: string }>()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  
  const activeTab = (searchParams.get('tab') || 'general') as MenuItemId

  const { data: host, isLoading, error } = useQuery({
    queryKey: ['hosts', domain],
    queryFn: () => api.getHost(domain!),
    enabled: !!domain,
  })

  const handleTabChange = (tabId: MenuItemId) => {
    setSearchParams({ tab: tabId })
  }

  const renderContent = () => {
    if (!domain) {
      return (
        <div className="text-center py-12 text-muted-foreground">
          Domain not specified
        </div>
      )
    }

    if (isLoading) {
      return (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      )
    }

    if (error || !host) {
      return (
        <div className="text-center py-12">
          <p className="text-destructive mb-4">Failed to load domain settings</p>
          <Button onClick={() => navigate('/')}>Back to Dashboard</Button>
        </div>
      )
    }

    switch (activeTab) {
      case 'general':
        return <GeneralSettings domain={domain} host={host} isLoading={isLoading} />
      case 'ssl':
        return <SSLSettings domain={domain} host={host} isLoading={isLoading} />
      case 'waf':
        return <WAFSettings domain={domain} />
      case 'rate-limiting':
        return <RateLimitingSettings domain={domain} />
      case 'ip-filtering':
        return <IPFilteringSettings domain={domain} />
      case 'logs':
        return <LogsSettings domain={domain} />
      case 'advanced':
        return <AdvancedSettings domain={domain} />
      default:
        return <GeneralSettings domain={domain} host={host} isLoading={isLoading} />
    }
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b bg-card/50 backdrop-blur-sm sticky top-0 z-50">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => navigate('/')}
            >
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back to Dashboard
            </Button>
            <div className="h-6 w-px bg-border" />
            <div className="flex items-center gap-2">
              <Globe className="h-5 w-5 text-primary" />
              <div>
                <h1 className="font-bold text-lg">{domain || 'Domain Settings'}</h1>
                <p className="text-xs text-muted-foreground">Domain configuration</p>
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6">
        <div className="flex gap-6">
          {/* Sidebar */}
          <aside className="w-64 flex-shrink-0">
            <Card className="sticky top-20">
              <nav className="p-2">
                <ul className="space-y-1">
                  {menuItems.map((item) => {
                    const Icon = item.icon
                    const isActive = activeTab === item.id
                    return (
                      <li key={item.id}>
                        <button
                          onClick={() => handleTabChange(item.id)}
                          className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                            isActive
                              ? 'bg-primary text-primary-foreground'
                              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
                          }`}
                        >
                          <Icon className="h-4 w-4" />
                          {item.label}
                        </button>
                      </li>
                    )
                  })}
                </ul>
              </nav>
            </Card>
          </aside>

          {/* Content Area */}
          <div className="flex-1 min-w-0">
            {renderContent()}
          </div>
        </div>
      </main>
    </div>
  )
}
