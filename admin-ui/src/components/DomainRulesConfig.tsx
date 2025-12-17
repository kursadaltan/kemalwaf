import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Shield, Search, Check, X, AlertTriangle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { api } from '@/lib/api'

interface DomainRulesConfigProps {
  domain: string
}

export function DomainRulesConfig({ domain }: DomainRulesConfigProps) {
  const queryClient = useQueryClient()
  const [searchQuery, setSearchQuery] = useState('')
  const [threshold, setThreshold] = useState(5)
  const [enabledRules, setEnabledRules] = useState<number[]>([])
  const [disabledRules, setDisabledRules] = useState<number[]>([])
  const [useCustomRules, setUseCustomRules] = useState(false)

  // Fetch domain rules config
  const { data: domainRulesData, isLoading } = useQuery({
    queryKey: ['domainRules', domain],
    queryFn: () => api.getDomainRules(domain),
    enabled: !!domain,
  })

  // Update local state when data is fetched
  useEffect(() => {
    if (domainRulesData) {
      setThreshold(domainRulesData.threshold)
      setEnabledRules(domainRulesData.enabled_rules || [])
      setDisabledRules(domainRulesData.disabled_rules || [])
      setUseCustomRules(
        (domainRulesData.enabled_rules && domainRulesData.enabled_rules.length > 0) ||
        (domainRulesData.disabled_rules && domainRulesData.disabled_rules.length > 0)
      )
    }
  }, [domainRulesData])

  const updateMutation = useMutation({
    mutationFn: (data: { threshold: number; enabled_rules: number[]; disabled_rules: number[] }) =>
      api.updateDomainRules(domain, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['domainRules', domain] })
      toast.success('Domain WAF configuration updated')
    },
    onError: (error: Error) => {
      toast.error(`Failed to update: ${error.message}`)
    },
  })

  const allRules = domainRulesData?.all_rules || []

  // Filter rules
  const filteredRules = allRules.filter(rule =>
    searchQuery === '' ||
    rule.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    rule.id.toString().includes(searchQuery) ||
    rule.category?.toLowerCase().includes(searchQuery.toLowerCase())
  )

  // Determine if a rule is enabled
  const isRuleEnabled = (ruleId: number): boolean => {
    if (!useCustomRules) return true // All rules enabled by default
    if (enabledRules.length > 0) {
      return enabledRules.includes(ruleId)
    }
    return !disabledRules.includes(ruleId)
  }

  // Toggle rule
  const toggleRule = (ruleId: number) => {
    if (enabledRules.length > 0) {
      // Using enabled list mode
      if (enabledRules.includes(ruleId)) {
        setEnabledRules(prev => prev.filter(id => id !== ruleId))
      } else {
        setEnabledRules(prev => [...prev, ruleId])
      }
    } else {
      // Using disabled list mode
      if (disabledRules.includes(ruleId)) {
        setDisabledRules(prev => prev.filter(id => id !== ruleId))
      } else {
        setDisabledRules(prev => [...prev, ruleId])
      }
    }
  }

  const handleSave = () => {
    updateMutation.mutate({
      threshold,
      enabled_rules: useCustomRules ? enabledRules : [],
      disabled_rules: useCustomRules ? disabledRules : [],
    })
  }

  const enableAll = () => {
    setEnabledRules([])
    setDisabledRules([])
  }

  const disableAll = () => {
    setEnabledRules([])
    setDisabledRules(allRules.map(r => r.id))
  }

  if (isLoading) {
    return (
      <div className="text-center py-8 text-muted-foreground">
        Loading WAF configuration...
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Threshold Configuration */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <AlertTriangle className="h-4 w-4" />
            Scoring Threshold
          </CardTitle>
          <CardDescription>
            Request will be blocked when total matched rule scores reach this threshold
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-4">
            <div className="space-y-2 flex-1 max-w-xs">
              <Label htmlFor="threshold">Threshold Value</Label>
              <Input
                id="threshold"
                type="number"
                min="1"
                value={threshold}
                onChange={(e) => setThreshold(parseInt(e.target.value) || 5)}
              />
            </div>
            <div className="text-sm text-muted-foreground pt-6">
              Lower = stricter, Higher = more permissive
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Rule Selection */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                <Shield className="h-4 w-4" />
                Rule Selection
              </CardTitle>
              <CardDescription>
                Choose which rules are active for this domain
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              <Label htmlFor="customRules" className="text-sm">Custom Rules</Label>
              <Switch
                id="customRules"
                checked={useCustomRules}
                onCheckedChange={setUseCustomRules}
              />
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {useCustomRules ? (
            <>
              {/* Search and Actions */}
              <div className="flex flex-col sm:flex-row gap-4">
                <div className="relative flex-1">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input
                    placeholder="Search rules..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="pl-9"
                  />
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={enableAll}>
                    Enable All
                  </Button>
                  <Button variant="outline" size="sm" onClick={disableAll}>
                    Disable All
                  </Button>
                </div>
              </div>

              {/* Stats */}
              <div className="flex gap-4 text-sm">
                <span className="text-muted-foreground">
                  Enabled: <span className="text-green-400 font-medium">
                    {allRules.filter(r => isRuleEnabled(r.id)).length}
                  </span>
                </span>
                <span className="text-muted-foreground">
                  Disabled: <span className="text-red-400 font-medium">
                    {allRules.filter(r => !isRuleEnabled(r.id)).length}
                  </span>
                </span>
                <span className="text-muted-foreground">
                  Total: <span className="font-medium">{allRules.length}</span>
                </span>
              </div>

              {/* Rules List */}
              <div className="max-h-80 overflow-y-auto border rounded-lg">
                {filteredRules.length === 0 ? (
                  <div className="p-4 text-center text-muted-foreground">
                    No rules found
                  </div>
                ) : (
                  <div className="divide-y">
                    {filteredRules.map(rule => {
                      const enabled = isRuleEnabled(rule.id)
                      return (
                        <div
                          key={rule.id}
                          className={`flex items-center justify-between p-3 hover:bg-accent/50 transition-colors cursor-pointer ${
                            !enabled ? 'opacity-60' : ''
                          }`}
                          onClick={() => toggleRule(rule.id)}
                        >
                          <div className="flex items-center gap-3 flex-1 min-w-0">
                            <div className={`h-8 w-8 rounded flex items-center justify-center flex-shrink-0 ${
                              enabled ? 'bg-green-500/20' : 'bg-red-500/20'
                            }`}>
                              {enabled ? (
                                <Check className="h-4 w-4 text-green-400" />
                              ) : (
                                <X className="h-4 w-4 text-red-400" />
                              )}
                            </div>
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <span className="font-mono text-xs text-muted-foreground">#{rule.id}</span>
                                <span className="text-sm truncate">{rule.name}</span>
                              </div>
                              <div className="flex items-center gap-2 mt-0.5">
                                {rule.category && (
                                  <Badge variant="outline" className="text-xs">
                                    {rule.category}
                                  </Badge>
                                )}
                                <span className="text-xs text-muted-foreground">
                                  Score: {rule.score}
                                </span>
                              </div>
                            </div>
                          </div>
                          <Switch
                            checked={enabled}
                            onCheckedChange={() => toggleRule(rule.id)}
                            onClick={(e) => e.stopPropagation()}
                          />
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="p-4 bg-muted/30 rounded-lg text-center">
              <p className="text-muted-foreground">
                All {allRules.length} rules are active for this domain.
              </p>
              <p className="text-sm text-muted-foreground mt-1">
                Enable "Custom Rules" to select specific rules.
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Save Button */}
      <div className="flex justify-end">
        <Button onClick={handleSave} disabled={updateMutation.isPending}>
          {updateMutation.isPending ? 'Saving...' : 'Save WAF Configuration'}
        </Button>
      </div>
    </div>
  )
}
