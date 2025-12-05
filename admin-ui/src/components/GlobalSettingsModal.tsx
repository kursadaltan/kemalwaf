import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Settings, Shield, Zap, Globe2, Ban, Loader2 } from 'lucide-react'
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
import { api, GlobalConfig, ApiError } from '@/lib/api'

interface GlobalSettingsModalProps {
  isOpen: boolean
  onClose: () => void
}

export function GlobalSettingsModal({ isOpen, onClose }: GlobalSettingsModalProps) {
  const queryClient = useQueryClient()

  // Form state
  const [mode, setMode] = useState<'enforce' | 'observe' | 'disabled'>('enforce')
  
  // Rate limiting
  const [rateLimitEnabled, setRateLimitEnabled] = useState(true)
  const [rateLimit, setRateLimit] = useState(100)
  const [rateWindow, setRateWindow] = useState('1s')
  const [blockDuration, setBlockDuration] = useState('300s')

  // GeoIP
  const [geoipEnabled, setGeoipEnabled] = useState(false)
  const [blockedCountries, setBlockedCountries] = useState('')
  const [allowedCountries, setAllowedCountries] = useState('')

  // IP Filtering
  const [ipFilterEnabled, setIpFilterEnabled] = useState(true)

  // Fetch current config
  const { data: config, isLoading } = useQuery({
    queryKey: ['config'],
    queryFn: api.getConfig,
    enabled: isOpen,
  })

  // Update form when config loads
  useEffect(() => {
    if (config) {
      setMode(config.mode)
      setRateLimitEnabled(config.rate_limiting.enabled)
      setRateLimit(config.rate_limiting.default_limit)
      setRateWindow(config.rate_limiting.window)
      setBlockDuration(config.rate_limiting.block_duration)
      setGeoipEnabled(config.geoip.enabled)
      setBlockedCountries(config.geoip.blocked_countries.join(', '))
      setAllowedCountries(config.geoip.allowed_countries.join(', '))
      setIpFilterEnabled(config.ip_filtering.enabled)
    }
  }, [config])

  const updateMutation = useMutation({
    mutationFn: (data: Partial<GlobalConfig>) => api.updateConfig(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['config'] })
      toast.success('Settings updated successfully')
      onClose()
    },
    onError: (error: ApiError) => {
      toast.error(error.message)
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    const data: Partial<GlobalConfig> = {
      mode,
      rate_limiting: {
        enabled: rateLimitEnabled,
        default_limit: rateLimit,
        window: rateWindow,
        block_duration: blockDuration,
      },
      geoip: {
        enabled: geoipEnabled,
        blocked_countries: blockedCountries.split(',').map(s => s.trim()).filter(Boolean),
        allowed_countries: allowedCountries.split(',').map(s => s.trim()).filter(Boolean),
      },
      ip_filtering: {
        enabled: ipFilterEnabled,
      },
    }

    updateMutation.mutate(data)
  }

  const isPending = updateMutation.isPending

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Settings className="h-5 w-5 text-primary" />
            Global Settings
          </DialogTitle>
        </DialogHeader>

        {isLoading ? (
          <div className="py-8 text-center">
            <Loader2 className="h-8 w-8 animate-spin mx-auto text-muted-foreground" />
            <p className="mt-2 text-muted-foreground">Loading settings...</p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* WAF Mode */}
            <div className="space-y-4">
              <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
                <Shield className="h-4 w-4" />
                WAF Mode
              </h3>
              <div className="space-y-2">
                <Label>Mode</Label>
                <Select value={mode} onValueChange={(v) => setMode(v as typeof mode)} disabled={isPending}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="enforce">
                      <span className="flex items-center gap-2">
                        <span className="h-2 w-2 rounded-full bg-green-500" />
                        Enforce - Block malicious requests
                      </span>
                    </SelectItem>
                    <SelectItem value="observe">
                      <span className="flex items-center gap-2">
                        <span className="h-2 w-2 rounded-full bg-yellow-500" />
                        Observe - Log only, don't block
                      </span>
                    </SelectItem>
                    <SelectItem value="disabled">
                      <span className="flex items-center gap-2">
                        <span className="h-2 w-2 rounded-full bg-red-500" />
                        Disabled - WAF is off
                      </span>
                    </SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <Separator />

            {/* Rate Limiting */}
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
                  <Zap className="h-4 w-4" />
                  Rate Limiting
                </h3>
                <Switch
                  checked={rateLimitEnabled}
                  onCheckedChange={setRateLimitEnabled}
                  disabled={isPending}
                />
              </div>

              {rateLimitEnabled && (
                <div className="space-y-4 pl-4 border-l-2 border-primary/20">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="rateLimit">Request Limit</Label>
                      <Input
                        id="rateLimit"
                        type="number"
                        value={rateLimit}
                        onChange={(e) => setRateLimit(parseInt(e.target.value) || 100)}
                        disabled={isPending}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="rateWindow">Window</Label>
                      <Select value={rateWindow} onValueChange={setRateWindow} disabled={isPending}>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="1s">1 second</SelectItem>
                          <SelectItem value="10s">10 seconds</SelectItem>
                          <SelectItem value="60s">1 minute</SelectItem>
                          <SelectItem value="300s">5 minutes</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="blockDuration">Block Duration</Label>
                    <Select value={blockDuration} onValueChange={setBlockDuration} disabled={isPending}>
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="60s">1 minute</SelectItem>
                        <SelectItem value="300s">5 minutes</SelectItem>
                        <SelectItem value="600s">10 minutes</SelectItem>
                        <SelectItem value="3600s">1 hour</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              )}
            </div>

            <Separator />

            {/* GeoIP Filtering */}
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
                  <Globe2 className="h-4 w-4" />
                  GeoIP Filtering
                </h3>
                <Switch
                  checked={geoipEnabled}
                  onCheckedChange={setGeoipEnabled}
                  disabled={isPending}
                />
              </div>

              {geoipEnabled && (
                <div className="space-y-4 pl-4 border-l-2 border-primary/20">
                  <div className="space-y-2">
                    <Label htmlFor="blockedCountries">Blocked Countries</Label>
                    <Input
                      id="blockedCountries"
                      placeholder="CN, RU, KP (comma separated)"
                      value={blockedCountries}
                      onChange={(e) => setBlockedCountries(e.target.value)}
                      disabled={isPending}
                    />
                    <p className="text-xs text-muted-foreground">
                      ISO country codes separated by commas
                    </p>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="allowedCountries">Allowed Countries Only</Label>
                    <Input
                      id="allowedCountries"
                      placeholder="US, GB, DE (leave empty for all)"
                      value={allowedCountries}
                      onChange={(e) => setAllowedCountries(e.target.value)}
                      disabled={isPending}
                    />
                    <p className="text-xs text-muted-foreground">
                      If set, only these countries are allowed
                    </p>
                  </div>
                </div>
              )}
            </div>

            <Separator />

            {/* IP Filtering */}
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-semibold flex items-center gap-2 text-muted-foreground">
                    <Ban className="h-4 w-4" />
                    IP Filtering
                  </h3>
                  <p className="text-xs text-muted-foreground mt-1">
                    Whitelist/blacklist configured in config files
                  </p>
                </div>
                <Switch
                  checked={ipFilterEnabled}
                  onCheckedChange={setIpFilterEnabled}
                  disabled={isPending}
                />
              </div>
            </div>

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
                    Saving...
                  </>
                ) : (
                  'Save Settings'
                )}
              </Button>
            </div>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}

