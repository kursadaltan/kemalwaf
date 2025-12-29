import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Plus, Edit, Trash2, Shield, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
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
import { api, Rule } from '@/lib/api'

interface CustomRulesSettingsProps {
  domain: string
}

export function CustomRulesSettings({ domain }: CustomRulesSettingsProps) {
  const queryClient = useQueryClient()
  const [searchQuery, setSearchQuery] = useState('')
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [editingRule, setEditingRule] = useState<Rule | null>(null)
  const [formData, setFormData] = useState({
    id: '',
    name: '',
    msg: '',
    pattern: '',
    operator: 'regex',
    action: 'deny',
    category: '',
    severity: 'MEDIUM',
    paranoia_level: '1',
    score: '',
    default_score: '1',
    tags: '',
    transforms: '',
    variables: 'ARGS',
  })

  // Fetch custom rules
  const { data, isLoading } = useQuery({
    queryKey: ['domainCustomRules', domain],
    queryFn: () => api.getDomainCustomRules(domain),
    enabled: !!domain,
  })

  const rules = data?.rules || []

  // Create/Update mutation
  const saveMutation = useMutation({
    mutationFn: (rule: Partial<Rule> & { id: number; msg: string; action: string }) => {
      if (editingRule) {
        return api.updateDomainCustomRule(domain, editingRule.id, rule)
      } else {
        return api.createDomainCustomRule(domain, rule)
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['domainCustomRules', domain] })
      toast.success(editingRule ? 'Custom rule updated' : 'Custom rule created')
      setIsDialogOpen(false)
      resetForm()
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Failed to save custom rule')
    },
  })

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: (id: number) => api.deleteDomainCustomRule(domain, id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['domainCustomRules', domain] })
      toast.success('Custom rule deleted')
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Failed to delete custom rule')
    },
  })

  const resetForm = () => {
    setEditingRule(null)
    setFormData({
      id: '',
      name: '',
      msg: '',
      pattern: '',
      operator: 'regex',
      action: 'deny',
      category: '',
      severity: 'MEDIUM',
      paranoia_level: '1',
      score: '',
      default_score: '1',
      tags: '',
      transforms: '',
      variables: 'ARGS',
    })
  }

  const handleEdit = (rule: Rule) => {
    setEditingRule(rule)
    setFormData({
      id: rule.id.toString(),
      name: rule.name || '',
      msg: rule.msg || '',
      pattern: rule.pattern || '',
      operator: rule.operator || 'regex',
      action: rule.action || 'deny',
      category: rule.category || '',
      severity: rule.severity || 'MEDIUM',
      paranoia_level: rule.paranoia_level?.toString() || '1',
      score: rule.score?.toString() || '',
      default_score: rule.default_score?.toString() || '1',
      tags: rule.tags?.join(', ') || '',
      transforms: rule.transforms?.join(', ') || '',
      variables: rule.variables?.[0]?.type || 'ARGS',
    })
    setIsDialogOpen(true)
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    const rule: Partial<Rule> & { id: number; msg: string; action: string } = {
      id: parseInt(formData.id),
      msg: formData.msg,
      action: formData.action,
      name: formData.name || undefined,
      pattern: formData.pattern || undefined,
      operator: formData.operator || undefined,
      category: formData.category || undefined,
      severity: formData.severity || undefined,
      paranoia_level: formData.paranoia_level ? parseInt(formData.paranoia_level) : undefined,
      score: formData.score ? parseInt(formData.score) : undefined,
      default_score: formData.default_score ? parseInt(formData.default_score) : 1,
      tags: formData.tags ? formData.tags.split(',').map((t) => t.trim()).filter(Boolean) : undefined,
      transforms: formData.transforms
        ? formData.transforms.split(',').map((t) => t.trim()).filter(Boolean)
        : undefined,
      variables: [
        {
          type: formData.variables,
        },
      ],
    }

    saveMutation.mutate(rule)
  }

  const filteredRules = rules.filter((rule) => {
    if (!searchQuery) return true
    const query = searchQuery.toLowerCase()
    return (
      rule.name?.toLowerCase().includes(query) ||
      rule.msg?.toLowerCase().includes(query) ||
      rule.pattern?.toLowerCase().includes(query) ||
      rule.category?.toLowerCase().includes(query) ||
      rule.id.toString().includes(query)
    )
  })

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="flex items-center gap-2">
                <Shield className="h-5 w-5" />
                Custom Rules - {domain}
              </CardTitle>
              <CardDescription>
                Create and manage custom WAF rules specific to this domain
              </CardDescription>
            </div>
            <Button onClick={() => {
              resetForm()
              setIsDialogOpen(true)
            }}>
              <Plus className="h-4 w-4 mr-2" />
              Add Custom Rule
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Search */}
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search rules..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>

          {/* Rules List */}
          {isLoading ? (
            <div className="text-center py-8 text-muted-foreground">Loading...</div>
          ) : filteredRules.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              {searchQuery ? 'No rules match your search' : 'No custom rules yet. Create one to get started.'}
            </div>
          ) : (
            <div className="space-y-2">
              {filteredRules.map((rule) => (
                <Card key={rule.id} className="p-4">
                  <div className="flex items-start justify-between">
                    <div className="flex-1 space-y-2">
                      <div className="flex items-center gap-2">
                        <Badge variant="outline">ID: {rule.id}</Badge>
                        {rule.name && <span className="font-medium">{rule.name}</span>}
                        {rule.category && (
                          <Badge variant="secondary">{rule.category}</Badge>
                        )}
                        {rule.severity && (
                          <Badge
                            variant={
                              rule.severity === 'CRITICAL'
                                ? 'destructive'
                                : rule.severity === 'HIGH'
                                  ? 'destructive'
                                  : 'outline'
                            }
                          >
                            {rule.severity}
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">{rule.msg}</p>
                      {rule.pattern && (
                        <div className="text-xs font-mono bg-muted p-2 rounded">
                          Pattern: {rule.pattern}
                        </div>
                      )}
                      <div className="flex items-center gap-4 text-xs text-muted-foreground">
                        <span>Action: {rule.action}</span>
                        {rule.score && <span>Score: {rule.score}</span>}
                        {rule.operator && <span>Operator: {rule.operator}</span>}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 ml-4">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => handleEdit(rule)}
                      >
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          if (confirm(`Delete custom rule ${rule.id}?`)) {
                            deleteMutation.mutate(rule.id)
                          }
                        }}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Add/Edit Dialog */}
      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {editingRule ? 'Edit Custom Rule' : 'Create Custom Rule'}
            </DialogTitle>
            <DialogDescription>
              {editingRule
                ? 'Update the custom rule configuration'
                : 'Create a new custom WAF rule for this domain'}
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="id">Rule ID *</Label>
                <Input
                  id="id"
                  type="number"
                  value={formData.id}
                  onChange={(e) => setFormData({ ...formData, id: e.target.value })}
                  required
                  disabled={!!editingRule}
                />
              </div>
              <div>
                <Label htmlFor="name">Name</Label>
                <Input
                  id="name"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                />
              </div>
            </div>

            <div>
              <Label htmlFor="msg">Message *</Label>
              <Input
                id="msg"
                value={formData.msg}
                onChange={(e) => setFormData({ ...formData, msg: e.target.value })}
                required
              />
            </div>

            <div>
              <Label htmlFor="pattern">Pattern (Regex)</Label>
              <Input
                id="pattern"
                value={formData.pattern}
                onChange={(e) => setFormData({ ...formData, pattern: e.target.value })}
                placeholder="(?i)(malicious|pattern)"
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="operator">Operator</Label>
                <Select
                  value={formData.operator}
                  onValueChange={(value) => setFormData({ ...formData, operator: value })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="regex">Regex</SelectItem>
                    <SelectItem value="equals">Equals</SelectItem>
                    <SelectItem value="contains">Contains</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="action">Action</Label>
                <Select
                  value={formData.action}
                  onValueChange={(value) => setFormData({ ...formData, action: value })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="deny">Deny</SelectItem>
                    <SelectItem value="allow">Allow</SelectItem>
                    <SelectItem value="log">Log</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="category">Category</Label>
                <Input
                  id="category"
                  value={formData.category}
                  onChange={(e) => setFormData({ ...formData, category: e.target.value })}
                  placeholder="xss, sqli, etc."
                />
              </div>
              <div>
                <Label htmlFor="severity">Severity</Label>
                <Select
                  value={formData.severity}
                  onValueChange={(value) => setFormData({ ...formData, severity: value })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="LOW">Low</SelectItem>
                    <SelectItem value="MEDIUM">Medium</SelectItem>
                    <SelectItem value="HIGH">High</SelectItem>
                    <SelectItem value="CRITICAL">Critical</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <Label htmlFor="paranoia_level">Paranoia Level</Label>
                <Input
                  id="paranoia_level"
                  type="number"
                  min="1"
                  max="4"
                  value={formData.paranoia_level}
                  onChange={(e) => setFormData({ ...formData, paranoia_level: e.target.value })}
                />
              </div>
              <div>
                <Label htmlFor="score">Score</Label>
                <Input
                  id="score"
                  type="number"
                  value={formData.score}
                  onChange={(e) => setFormData({ ...formData, score: e.target.value })}
                  placeholder="Optional"
                />
              </div>
              <div>
                <Label htmlFor="default_score">Default Score</Label>
                <Input
                  id="default_score"
                  type="number"
                  value={formData.default_score}
                  onChange={(e) => setFormData({ ...formData, default_score: e.target.value })}
                />
              </div>
            </div>

            <div>
              <Label htmlFor="variables">Variables</Label>
              <Select
                value={formData.variables}
                onValueChange={(value) => setFormData({ ...formData, variables: value })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="ARGS">ARGS</SelectItem>
                  <SelectItem value="BODY">BODY</SelectItem>
                  <SelectItem value="HEADERS">HEADERS</SelectItem>
                  <SelectItem value="URI">URI</SelectItem>
                  <SelectItem value="QUERY_STRING">QUERY_STRING</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div>
              <Label htmlFor="tags">Tags (comma-separated)</Label>
              <Input
                id="tags"
                value={formData.tags}
                onChange={(e) => setFormData({ ...formData, tags: e.target.value })}
                placeholder="attack-xss, custom-rule"
              />
            </div>

            <div>
              <Label htmlFor="transforms">Transforms (comma-separated)</Label>
              <Input
                id="transforms"
                value={formData.transforms}
                onChange={(e) => setFormData({ ...formData, transforms: e.target.value })}
                placeholder="url_decode, lowercase"
              />
            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setIsDialogOpen(false)
                  resetForm()
                }}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={saveMutation.isPending}>
                {saveMutation.isPending
                  ? 'Saving...'
                  : editingRule
                    ? 'Update'
                    : 'Create'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
