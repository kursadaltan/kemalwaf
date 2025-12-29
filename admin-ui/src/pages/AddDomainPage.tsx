import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Globe, Link, Lock, ArrowLeft, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { api, CreateHostData, ApiError } from '@/lib/api'

export function AddDomainPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  // Form state
  const [domain, setDomain] = useState('')
  const [upstreamUrl, setUpstreamUrl] = useState('')
  const [upstreamHostHeader, setUpstreamHostHeader] = useState('')
  const [preserveHost, setPreserveHost] = useState(true)
  const [verifySsl, setVerifySsl] = useState(true)
  
  // SSL state
  const [sslEnabled, setSslEnabled] = useState(false)
  const [sslType, setSslType] = useState<'letsencrypt' | 'custom' | 'none'>('letsencrypt')
  const [sslEmail, setSslEmail] = useState('')

  const createMutation = useMutation({
    mutationFn: (data: CreateHostData) => api.createHost(data),
    onSuccess: async (response) => {
      await queryClient.invalidateQueries({ queryKey: ['hosts'] })
      toast.success('Proxy host created successfully')
      // Navigate to domain settings page
      navigate(`/domains/${response.domain}?tab=general`)
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
    if (sslEnabled && sslType === 'letsencrypt') {
      if (!sslEmail?.trim()) {
        toast.error('Email address is required for Let\'s Encrypt certificates')
        return
      }
      // Basic email format validation
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
      if (!emailRegex.test(sslEmail.trim())) {
        toast.error('Please enter a valid email address')
        return
      }
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

    createMutation.mutate(data)
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
              <h1 className="font-bold text-lg">Add New Domain</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 max-w-3xl">
        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Domain Configuration */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Globe className="h-5 w-5" />
                Domain Configuration
              </CardTitle>
              <CardDescription>
                Basic domain and upstream server settings
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="domain">Domain Name *</Label>
                <Input
                  id="domain"
                  placeholder="example.com"
                  value={domain}
                  onChange={(e) => setDomain(e.target.value)}
                  disabled={createMutation.isPending}
                  required
                />
              </div>
            </CardContent>
          </Card>

          {/* Upstream Configuration */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Link className="h-5 w-5" />
                Upstream Configuration
              </CardTitle>
              <CardDescription>
                Configure the backend server to proxy requests to
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="upstream">Upstream URL *</Label>
                <Input
                  id="upstream"
                  placeholder="http://localhost:8080"
                  value={upstreamUrl}
                  onChange={(e) => setUpstreamUrl(e.target.value)}
                  disabled={createMutation.isPending}
                  required
                />
                <p className="text-xs text-muted-foreground">
                  The backend server to proxy requests to
                </p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="hostHeader">Custom Host Header</Label>
                <Input
                  id="hostHeader"
                  placeholder={domain || 'Leave empty to use domain'}
                  value={upstreamHostHeader}
                  onChange={(e) => setUpstreamHostHeader(e.target.value)}
                  disabled={createMutation.isPending}
                />
                <p className="text-xs text-muted-foreground">
                  Override the Host header sent to upstream
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
                  disabled={createMutation.isPending}
                />
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
                  disabled={createMutation.isPending}
                />
              </div>
            </CardContent>
          </Card>

          {/* SSL Configuration */}
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="flex items-center gap-2">
                    <Lock className="h-5 w-5" />
                    SSL/TLS
                  </CardTitle>
                  <CardDescription>
                    Configure SSL/TLS certificates for this domain
                  </CardDescription>
                </div>
                <Switch
                  checked={sslEnabled}
                  onCheckedChange={setSslEnabled}
                  disabled={createMutation.isPending}
                />
              </div>
            </CardHeader>
            {sslEnabled && (
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label>SSL Type</Label>
                  <Select
                    value={sslType}
                    onValueChange={(v) => setSslType(v as typeof sslType)}
                    disabled={createMutation.isPending}
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
                      disabled={createMutation.isPending}
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
              </CardContent>
            )}
          </Card>

          {/* Actions */}
          <div className="flex justify-end gap-2">
            <Button 
              type="button" 
              variant="outline" 
              onClick={() => navigate('/')} 
              disabled={createMutation.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={createMutation.isPending}>
              {createMutation.isPending ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Creating...
                </>
              ) : (
                'Create Domain'
              )}
            </Button>
          </div>
        </form>
      </main>
    </div>
  )
}
