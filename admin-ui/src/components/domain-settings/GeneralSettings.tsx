import { useState, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Globe, Link, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { api, ProxyHost, CreateHostData, ApiError } from '@/lib/api'

interface GeneralSettingsProps {
  domain: string
  host: ProxyHost | null
  isLoading: boolean
}

export function GeneralSettings({ domain, host, isLoading: hostLoading }: GeneralSettingsProps) {
  const queryClient = useQueryClient()

  // Form state
  const [upstreamUrl, setUpstreamUrl] = useState('')
  const [upstreamHostHeader, setUpstreamHostHeader] = useState('')
  const [preserveHost, setPreserveHost] = useState(true)
  const [verifySsl, setVerifySsl] = useState(true)

  // Update form when host data changes
  useEffect(() => {
    if (host) {
      setUpstreamUrl(host.default_upstream)
      setUpstreamHostHeader(host.upstream_host_header)
      setPreserveHost(host.preserve_original_host)
      setVerifySsl(host.verify_ssl)
    }
  }, [host])

  const updateMutation = useMutation({
    mutationFn: (data: CreateHostData) => api.updateHost(domain, data),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['hosts'] })
      await queryClient.invalidateQueries({ queryKey: ['hosts', domain] })
      toast.success('Domain settings updated successfully')
    },
    onError: (error: ApiError) => {
      toast.error(error.message)
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!upstreamUrl) {
      toast.error('Upstream URL is required')
      return
    }

    const data: CreateHostData = {
      domain,
      upstream_url: upstreamUrl,
      upstream_host_header: upstreamHostHeader || domain,
      preserve_host: preserveHost,
      verify_ssl: verifySsl,
      ssl_type: host?.ssl.type || 'none',
      ssl_email: host?.ssl.letsencrypt_email,
    }

    updateMutation.mutate(data)
  }

  if (hostLoading) {
    return (
      <div className="text-center py-8 text-muted-foreground">
        Loading domain settings...
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
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
            <Label htmlFor="domain">Domain Name</Label>
            <Input
              id="domain"
              value={domain}
              disabled
              className="bg-muted"
            />
            <p className="text-xs text-muted-foreground">
              Domain name cannot be changed after creation
            </p>
          </div>
        </CardContent>
      </Card>

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
              disabled={updateMutation.isPending}
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
              disabled={updateMutation.isPending}
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
              disabled={updateMutation.isPending}
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
              disabled={updateMutation.isPending}
            />
          </div>
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
