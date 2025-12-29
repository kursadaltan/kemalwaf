import { useState, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Lock, Loader2 } from 'lucide-react'
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
import { api, ProxyHost, CreateHostData, ApiError } from '@/lib/api'

interface SSLSettingsProps {
  domain: string
  host: ProxyHost | null
  isLoading: boolean
}

export function SSLSettings({ domain, host, isLoading: hostLoading }: SSLSettingsProps) {
  const queryClient = useQueryClient()

  // SSL state
  const [sslEnabled, setSslEnabled] = useState(false)
  const [sslType, setSslType] = useState<'letsencrypt' | 'custom' | 'none'>('letsencrypt')
  const [sslEmail, setSslEmail] = useState('')

  // Update form when host data changes
  useEffect(() => {
    if (host) {
      setSslEnabled(host.ssl.enabled)
      setSslType(host.ssl.type)
      setSslEmail(host.ssl.letsencrypt_email || '')
    }
  }, [host])

  const updateMutation = useMutation({
    mutationFn: (data: CreateHostData) => api.updateHost(domain, data),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['hosts'] })
      await queryClient.invalidateQueries({ queryKey: ['hosts', domain] })
      toast.success('SSL settings updated successfully')
    },
    onError: (error: ApiError) => {
      toast.error(error.message)
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

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
      upstream_url: host?.default_upstream || '',
      upstream_host_header: host?.upstream_host_header,
      preserve_host: host?.preserve_original_host,
      verify_ssl: host?.verify_ssl,
      ssl_type: sslEnabled ? sslType : 'none',
      ssl_email: sslType === 'letsencrypt' ? sslEmail?.trim() : undefined,
    }

    updateMutation.mutate(data)
  }

  if (hostLoading) {
    return (
      <div className="text-center py-8 text-muted-foreground">
        Loading SSL settings...
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Lock className="h-5 w-5" />
            SSL/TLS Configuration
          </CardTitle>
          <CardDescription>
            Configure SSL/TLS certificates for this domain
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label>Enable SSL/TLS</Label>
              <p className="text-xs text-muted-foreground">
                Enable HTTPS for this domain
              </p>
            </div>
            <Switch
              checked={sslEnabled}
              onCheckedChange={setSslEnabled}
              disabled={updateMutation.isPending}
            />
          </div>

          {sslEnabled && (
            <div className="space-y-4 pl-4 border-l-2 border-primary/20">
              <div className="space-y-2">
                <Label>SSL Type</Label>
                <Select
                  value={sslType}
                  onValueChange={(v) => setSslType(v as typeof sslType)}
                  disabled={updateMutation.isPending}
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
                    disabled={updateMutation.isPending}
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
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Button type="submit" disabled={updateMutation.isPending}>
          {updateMutation.isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Saving...
            </>
          ) : (
            'Save Changes'
          )}
        </Button>
      </div>
    </form>
  )
}
