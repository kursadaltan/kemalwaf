import { useQuery } from '@tanstack/react-query'
import { Zap } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { api } from '@/lib/api'

interface RateLimitingSettingsProps {
  domain: string
}

export function RateLimitingSettings({ domain: _domain }: RateLimitingSettingsProps) {
  const { data: config, isLoading } = useQuery({
    queryKey: ['config'],
    queryFn: api.getConfig,
  })

  if (isLoading) {
    return (
      <div className="text-center py-8 text-muted-foreground">
        Loading rate limiting settings...
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Zap className="h-5 w-5" />
            Rate Limiting
          </CardTitle>
          <CardDescription>
            Rate limiting configuration for this domain
          </CardDescription>
        </CardHeader>
        <CardContent>
          {config?.rate_limiting ? (
            <div className="space-y-4">
              <div className="p-4 bg-muted/30 rounded-lg">
                <p className="text-sm text-muted-foreground mb-2">
                  Rate limiting is currently configured globally. Domain-specific rate limiting is not yet implemented.
                </p>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Enabled:</span>
                    <span className="font-medium">{config.rate_limiting.enabled ? 'Yes' : 'No'}</span>
                  </div>
                  {config.rate_limiting.enabled && (
                    <>
                      <div className="flex justify-between">
                        <span className="text-muted-foreground">Default Limit:</span>
                        <span className="font-medium">{config.rate_limiting.default_limit} requests</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-muted-foreground">Window:</span>
                        <span className="font-medium">{config.rate_limiting.window}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-muted-foreground">Block Duration:</span>
                        <span className="font-medium">{config.rate_limiting.block_duration}</span>
                      </div>
                    </>
                  )}
                </div>
              </div>
            </div>
          ) : (
            <div className="p-4 bg-muted/30 rounded-lg text-center text-muted-foreground">
              Rate limiting configuration not available
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
