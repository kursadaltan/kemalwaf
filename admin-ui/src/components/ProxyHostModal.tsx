import { useState, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Globe, Link, Lock, Settings2, ChevronDown, Loader2, Shield } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Separator } from '@/components/ui/separator'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import { api, ProxyHost, CreateHostData, ApiError } from '@/lib/api'
import { DomainRulesConfig } from '@/components/DomainRulesConfig'

interface ProxyHostModalProps {
  isOpen: boolean
  onClose: () => void
  host: ProxyHost | null
}

export function ProxyHostModal({ isOpen, onClose, host }: ProxyHostModalProps) {
  const queryClient = useQueryClient()
  const isEditing = !!host

  // Form state
  const [domain, setDomain] = useState('')
  const [upstreamUrl, setUpstreamUrl] = useState('')
  const [upstreamHostHeader, setUpstreamHostHeader] = useState('')
  const [preserveHost, setPreserveHost] = useState(true)
  const [verifySsl, setVerifySsl] = useState(true)
  
  // SSL state
  const [sslEnabled, setSslEnabled] = useState(true)
  const [sslType, setSslType] = useState<'letsencrypt' | 'custom' | 'none'>('letsencrypt')
  const [sslEmail, setSslEmail] = useState('')
  
  // Advanced settings
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [showWafSettings, setShowWafSettings] = useState(false)

  // Reset form when modal opens/closes or host changes
  useEffect(() => {
    if (isOpen) {
      if (host) {
        setDomain(host.domain)
        setUpstreamUrl(host.default_upstream)
        setUpstreamHostHeader(host.upstream_host_header)
        setPreserveHost(host.preserve_original_host)
        setVerifySsl(host.verify_ssl)
        setSslEnabled(host.ssl.enabled)
        setSslType(host.ssl.type)
        setSslEmail(host.ssl.letsencrypt_email || '')
      } else {
        // Reset to defaults for new host
        setDomain('')
        setUpstreamUrl('')
        setUpstreamHostHeader('')
        setPreserveHost(true)
        setVerifySsl(true)
        setSslEnabled(true)
        setSslType('letsencrypt')
        setSslEmail('')
        setShowAdvanced(false)
      }
    }
  }, [isOpen, host])

  const createMutation = useMutation({
    mutationFn: (data: CreateHostData) => api.createHost(data),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['hosts'] })
      await queryClient.refetchQueries({ queryKey: ['hosts'] })
      toast.success('Proxy host created successfully')
      onClose()
    },
    onError: (error: ApiError) => {
      toast.error(error.message)
    },
  })

  const updateMutation = useMutation({
    mutationFn: (data: CreateHostData) => api.updateHost(host!.domain, data),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['hosts'] })
      await queryClient.refetchQueries({ queryKey: ['hosts'] })
      toast.success('Proxy host updated successfully')
      onClose()
    },
    onError: (error: ApiError) => {
      toast.error(error.message)
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!domain || !upstreamUrl) {
      toast.error('Domain and upstream URL are required')
      return
    }

    // Validate Let's Encrypt email if SSL is enabled and type is letsencrypt
    if (sslEnabled && sslType === 'letsencrypt' && !sslEmail?.trim()) {
      toast.error('Email address is required for Let\'s Encrypt certificates')
      return
    }

    const data: CreateHostData = {
      domain,
      upstream_url: upstreamUrl,
      upstream_host_header: upstreamHostHeader || domain,
      preserve_host: preserveHost,
      verify_ssl: verifySsl,
      ssl_type: sslEnabled ? sslType : 'none',
      ssl_email: sslType === 'letsencrypt' ? sslEmail?.trim() : undefined,
    }

    if (isEditing) {
      updateMutation.mutate(data)
    } else {
      createMutation.mutate(data)
    }
  }

  const isPending = createMutation.isPending || updateMutation.isPending

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Globe className="h-5 w-5 text-primary" />
            {isEditing ? 'Edit Proxy Host' : 'Add Proxy Host'}
          </DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Domain Configuration */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
              <Globe className="h-4 w-4" />
              Domain Configuration
            </h3>
            <div className="space-y-2">
              <Label htmlFor="domain">Domain Name *</Label>
              <Input
                id="domain"
                placeholder="example.com"
                value={domain}
                onChange={(e) => setDomain(e.target.value)}
                disabled={isEditing || isPending}
              />
            </div>
          </div>

          <Separator />

          {/* Upstream Configuration */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
              <Link className="h-4 w-4" />
              Upstream Configuration
            </h3>
            <div className="space-y-2">
              <Label htmlFor="upstream">Upstream URL *</Label>
              <Input
                id="upstream"
                placeholder="http://localhost:8080"
                value={upstreamUrl}
                onChange={(e) => setUpstreamUrl(e.target.value)}
                disabled={isPending}
              />
              <p className="text-xs text-muted-foreground">
                The backend server to proxy requests to
              </p>
            </div>
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>Preserve Host Header</Label>
                <p className="text-xs text-muted-foreground">
                  Send original host header to upstream
                </p>
              </div>
              <Switch
                checked={preserveHost}
                onCheckedChange={setPreserveHost}
                disabled={isPending}
              />
            </div>
          </div>

          <Separator />

          {/* SSL Configuration */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
                <Lock className="h-4 w-4" />
                SSL/TLS
              </h3>
              <Switch
                checked={sslEnabled}
                onCheckedChange={setSslEnabled}
                disabled={isPending}
              />
            </div>

            {sslEnabled && (
              <div className="space-y-4 pl-4 border-l-2 border-primary/20">
                <div className="space-y-2">
                  <Label>SSL Type</Label>
                  <Select
                    value={sslType}
                    onValueChange={(v) => setSslType(v as typeof sslType)}
                    disabled={isPending}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="letsencrypt">
                        Let's Encrypt (Automatic)
                      </SelectItem>
                      <SelectItem value="custom">
                        Custom Certificate
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                {sslType === 'letsencrypt' && (
                  <div className="space-y-2">
                    <Label htmlFor="sslEmail">Email Address *</Label>
                    <Input
                      id="sslEmail"
                      type="email"
                      placeholder="admin@example.com"
                      value={sslEmail}
                      onChange={(e) => setSslEmail(e.target.value)}
                      disabled={isPending}
                      required
                    />
                    <p className="text-xs text-muted-foreground">
                      Required for Let's Encrypt certificate issuance and renewal notices
                    </p>
                  </div>
                )}

                {sslType === 'custom' && (
                  <div className="p-3 rounded-lg bg-muted/50 text-sm text-muted-foreground">
                    Custom certificates can be configured manually in the WAF config file.
                  </div>
                )}
              </div>
            )}
          </div>

          <Separator />

          {/* Advanced Settings */}
          <Collapsible open={showAdvanced} onOpenChange={setShowAdvanced}>
            <CollapsibleTrigger asChild>
              <Button
                type="button"
                variant="ghost"
                className="w-full justify-between"
              >
                <span className="flex items-center gap-2">
                  <Settings2 className="h-4 w-4" />
                  Advanced Settings
                </span>
                <ChevronDown
                  className={`h-4 w-4 transition-transform ${showAdvanced ? 'rotate-180' : ''}`}
                />
              </Button>
            </CollapsibleTrigger>
            <CollapsibleContent className="space-y-4 pt-4">
              <div className="space-y-2">
                <Label htmlFor="hostHeader">Custom Host Header</Label>
                <Input
                  id="hostHeader"
                  placeholder={domain || 'Leave empty to use domain'}
                  value={upstreamHostHeader}
                  onChange={(e) => setUpstreamHostHeader(e.target.value)}
                  disabled={isPending}
                />
                <p className="text-xs text-muted-foreground">
                  Override the Host header sent to upstream
                </p>
              </div>
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>Verify Upstream SSL</Label>
                  <p className="text-xs text-muted-foreground">
                    Verify SSL certificate of upstream server
                  </p>
                </div>
                <Switch
                  checked={verifySsl}
                  onCheckedChange={setVerifySsl}
                  disabled={isPending}
                />
              </div>
            </CollapsibleContent>
          </Collapsible>

          {/* WAF Settings - Only show for editing existing hosts */}
          {isEditing && (
            <>
              <Separator />
              <Collapsible open={showWafSettings} onOpenChange={setShowWafSettings}>
                <CollapsibleTrigger asChild>
                  <Button
                    type="button"
                    variant="ghost"
                    className="w-full justify-between"
                  >
                    <span className="flex items-center gap-2">
                      <Shield className="h-4 w-4" />
                      WAF Rules & Scoring
                    </span>
                    <ChevronDown
                      className={`h-4 w-4 transition-transform ${showWafSettings ? 'rotate-180' : ''}`}
                    />
                  </Button>
                </CollapsibleTrigger>
                <CollapsibleContent className="pt-4">
                  <DomainRulesConfig domain={domain} />
                </CollapsibleContent>
              </Collapsible>
            </>
          )}

          <Separator />

          {/* Actions */}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onClose} disabled={isPending}>
              Cancel
            </Button>
            <Button type="submit" disabled={isPending}>
              {isPending ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {isEditing ? 'Saving...' : 'Creating...'}
                </>
              ) : (
                <>{isEditing ? 'Save Changes' : 'Create Host'}</>
              )}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}

