import { useQuery } from '@tanstack/react-query'
import { Ban } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { api } from '@/lib/api'

interface IPFilteringSettingsProps {
  domain: string
}

export function IPFilteringSettings({ domain: _domain }: IPFilteringSettingsProps) {
  const { data: config, isLoading } = useQuery({
    queryKey: ['config'],
    queryFn: api.getConfig,
  })

  if (isLoading) {
    return (
      <div className="text-center py-8 text-muted-foreground">
        Loading IP filtering settings...
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Ban className="h-5 w-5" />
            IP Filtering
          </CardTitle>
          <CardDescription>
            IP whitelist and blacklist configuration for this domain
          </CardDescription>
        </CardHeader>
        <CardContent>
          {config?.ip_filtering ? (
            <div className="space-y-4">
              <div className="p-4 bg-muted/30 rounded-lg">
                <p className="text-sm text-muted-foreground mb-2">
                  IP filtering is currently configured globally. Domain-specific IP filtering is not yet implemented.
                </p>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Enabled:</span>
                    <span className="font-medium">{config.ip_filtering.enabled ? 'Yes' : 'No'}</span>
                  </div>
                  {config.ip_filtering.enabled && (
                    <>
                      {config.ip_filtering.whitelist_file && (
                        <div className="flex justify-between">
                          <span className="text-muted-foreground">Whitelist File:</span>
                          <span className="font-mono text-xs">{config.ip_filtering.whitelist_file}</span>
                        </div>
                      )}
                      {config.ip_filtering.blacklist_file && (
                        <div className="flex justify-between">
                          <span className="text-muted-foreground">Blacklist File:</span>
                          <span className="font-mono text-xs">{config.ip_filtering.blacklist_file}</span>
                        </div>
                      )}
                    </>
                  )}
                </div>
              </div>
            </div>
          ) : (
            <div className="p-4 bg-muted/30 rounded-lg text-center text-muted-foreground">
              IP filtering configuration not available
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
