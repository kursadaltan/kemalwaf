import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { 
  Shield, 
  Plus, 
  Search,
  RefreshCw,
  ChevronDown,
  Trash2,
  Edit,
  ArrowLeft,
  FileText,
  Filter,
  AlertTriangle,
  CheckCircle2,
  XCircle
} from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { 
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { api, Rule } from '@/lib/api'
import { RuleEditor } from '@/components/RuleEditor'

interface RuleCardProps {
  rule: Rule
  onEdit: () => void
  onDelete: () => void
}

function RuleCard({ rule, onEdit, onDelete }: RuleCardProps) {
  const [isOpen, setIsOpen] = useState(false)

  const getSeverityColor = (severity?: string) => {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return 'bg-red-500/20 text-red-400 border-red-500/30'
      case 'high':
        return 'bg-orange-500/20 text-orange-400 border-orange-500/30'
      case 'medium':
        return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30'
      case 'low':
        return 'bg-blue-500/20 text-blue-400 border-blue-500/30'
      default:
        return 'bg-gray-500/20 text-gray-400 border-gray-500/30'
    }
  }

  const getActionIcon = (action: string) => {
    switch (action) {
      case 'deny':
        return <XCircle className="h-4 w-4 text-red-400" />
      case 'allow':
        return <CheckCircle2 className="h-4 w-4 text-green-400" />
      default:
        return <AlertTriangle className="h-4 w-4 text-yellow-400" />
    }
  }

  return (
    <Collapsible open={isOpen} onOpenChange={setIsOpen}>
      <Card className="card-hover overflow-hidden">
        <CollapsibleTrigger asChild>
          <div className="p-4 cursor-pointer hover:bg-accent/50 transition-colors">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3 flex-1 min-w-0">
                <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
                  {getActionIcon(rule.action)}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-mono text-sm text-muted-foreground">#{rule.id}</span>
                    <h3 className="font-semibold truncate">{rule.name || rule.msg}</h3>
                  </div>
                  <div className="flex items-center gap-2 mt-1 flex-wrap">
                    {rule.category && (
                      <Badge variant="outline" className="text-xs">
                        {rule.category}
                      </Badge>
                    )}
                    {rule.severity && (
                      <Badge className={`text-xs ${getSeverityColor(rule.severity)}`}>
                        {rule.severity}
                      </Badge>
                    )}
                    <span className="text-xs text-muted-foreground">
                      Score: {rule.score ?? rule.default_score}
                    </span>
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-2 ml-2">
                <ChevronDown className={`h-5 w-5 text-muted-foreground transition-transform ${isOpen ? 'rotate-180' : ''}`} />
              </div>
            </div>
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div className="px-4 pb-4 space-y-4 border-t pt-4 bg-muted/30">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <p className="text-muted-foreground">Operator</p>
                <p className="font-mono text-xs">{rule.operator || 'regex'}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Action</p>
                <p className="font-mono text-xs">{rule.action}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Score</p>
                <p className="font-mono text-xs">{rule.score ?? rule.default_score}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Paranoia Level</p>
                <p className="font-mono text-xs">{rule.paranoia_level ?? 1}</p>
              </div>
            </div>

            {rule.pattern && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Pattern</p>
                <pre className="bg-black/30 p-2 rounded text-xs overflow-x-auto">
                  {rule.pattern}
                </pre>
              </div>
            )}

            {rule.msg && rule.name && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Message</p>
                <p className="text-sm">{rule.msg}</p>
              </div>
            )}

            {rule.variables && rule.variables.length > 0 && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Variables</p>
                <div className="flex gap-2 flex-wrap">
                  {rule.variables.map((v, i) => (
                    <Badge key={i} variant="secondary" className="text-xs">
                      {v.type}
                      {v.names && v.names.length > 0 && `: ${v.names.join(', ')}`}
                    </Badge>
                  ))}
                </div>
              </div>
            )}

            {rule.transforms && rule.transforms.length > 0 && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Transforms</p>
                <div className="flex gap-2 flex-wrap">
                  {rule.transforms.map((t, i) => (
                    <Badge key={i} variant="outline" className="text-xs">
                      {t}
                    </Badge>
                  ))}
                </div>
              </div>
            )}

            {rule.tags && rule.tags.length > 0 && (
              <div>
                <p className="text-muted-foreground text-sm mb-1">Tags</p>
                <div className="flex gap-2 flex-wrap">
                  {rule.tags.map((t, i) => (
                    <Badge key={i} variant="outline" className="text-xs">
                      {t}
                    </Badge>
                  ))}
                </div>
              </div>
            )}

            {rule.source_file && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <FileText className="h-3 w-3" />
                {rule.source_file}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" size="sm" onClick={onEdit}>
                <Edit className="h-4 w-4 mr-1" />
                Edit
              </Button>
              <Button variant="destructive" size="sm" onClick={onDelete}>
                <Trash2 className="h-4 w-4 mr-1" />
                Delete
              </Button>
            </div>
          </div>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  )
}

interface RulesPageProps {
  onBack?: () => void
}

export function RulesPage({ onBack }: RulesPageProps) {
  const queryClient = useQueryClient()
  const [searchQuery, setSearchQuery] = useState('')
  const [categoryFilter, setCategoryFilter] = useState<string>('all')
  const [severityFilter, setSeverityFilter] = useState<string>('all')
  const [isEditorOpen, setIsEditorOpen] = useState(false)
  const [editingRule, setEditingRule] = useState<Rule | null>(null)

  // Fetch rules
  const { data: rulesData, isLoading, error } = useQuery({
    queryKey: ['rules'],
    queryFn: () => api.getRules(),
    retry: 1,
  })

  const reloadMutation = useMutation({
    mutationFn: api.reloadRules,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['rules'] })
      toast.success(`Rules reloaded: ${data.count} rules loaded`)
    },
    onError: () => {
      toast.error('Failed to reload rules')
    },
  })

  const deleteMutation = useMutation({
    mutationFn: api.deleteRule,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rules'] })
      toast.success('Rule deleted')
    },
    onError: () => {
      toast.error('Failed to delete rule')
    },
  })

  const rules = rulesData?.rules || []
  const categories = rulesData?.categories || []

  // Filter rules
  const filteredRules = rules.filter(rule => {
    const matchesSearch = searchQuery === '' || 
      rule.msg.toLowerCase().includes(searchQuery.toLowerCase()) ||
      rule.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      rule.id.toString().includes(searchQuery) ||
      rule.pattern?.toLowerCase().includes(searchQuery.toLowerCase())
    
    const matchesCategory = categoryFilter === 'all' || rule.category === categoryFilter
    const matchesSeverity = severityFilter === 'all' || rule.severity?.toLowerCase() === severityFilter

    return matchesSearch && matchesCategory && matchesSeverity
  })

  const handleEdit = (rule: Rule) => {
    setEditingRule(rule)
    setIsEditorOpen(true)
  }

  const handleDelete = (id: number) => {
    if (confirm(`Are you sure you want to delete rule #${id}?`)) {
      deleteMutation.mutate(id)
    }
  }

  const handleEditorClose = () => {
    setIsEditorOpen(false)
    setEditingRule(null)
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b bg-card/50 backdrop-blur-sm sticky top-0 z-50">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            {onBack && (
              <Button variant="ghost" size="sm" onClick={onBack}>
                <ArrowLeft className="h-4 w-4 mr-1" />
                Back
              </Button>
            )}
            <div className="h-9 w-9 rounded-lg bg-primary flex items-center justify-center">
              <Shield className="h-5 w-5 text-primary-foreground" />
            </div>
            <div>
              <h1 className="font-bold text-lg">Global Rules</h1>
              <p className="text-xs text-muted-foreground">Manage WAF Rules</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => reloadMutation.mutate()}
              disabled={reloadMutation.isPending}
            >
              <RefreshCw className={`h-4 w-4 mr-1 ${reloadMutation.isPending ? 'animate-spin' : ''}`} />
              Reload
            </Button>
            <Button onClick={() => setIsEditorOpen(true)}>
              <Plus className="h-4 w-4 mr-1" />
              Add Rule
            </Button>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold">{rules.length}</div>
              <p className="text-sm text-muted-foreground">Total Rules</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold">{categories.length}</div>
              <p className="text-sm text-muted-foreground">Categories</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold">
                {rules.filter(r => r.severity?.toLowerCase() === 'critical').length}
              </div>
              <p className="text-sm text-muted-foreground">Critical Rules</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold">
                {rules.filter(r => r.action === 'deny').length}
              </div>
              <p className="text-sm text-muted-foreground">Deny Rules</p>
            </CardContent>
          </Card>
        </div>

        {/* Filters */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <Filter className="h-4 w-4" />
              Filters
            </CardTitle>
          </CardHeader>
          <CardContent>
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
              <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                <SelectTrigger className="w-full sm:w-48">
                  <SelectValue placeholder="Category" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Categories</SelectItem>
                  {categories.map(cat => (
                    <SelectItem key={cat} value={cat}>{cat}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={severityFilter} onValueChange={setSeverityFilter}>
                <SelectTrigger className="w-full sm:w-48">
                  <SelectValue placeholder="Severity" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Severities</SelectItem>
                  <SelectItem value="critical">Critical</SelectItem>
                  <SelectItem value="high">High</SelectItem>
                  <SelectItem value="medium">Medium</SelectItem>
                  <SelectItem value="low">Low</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        {/* Rules List */}
        <div className="space-y-3">
          {error && (
            <Card className="p-4 border-destructive bg-destructive/10">
              <p className="text-destructive font-semibold">Error loading rules</p>
              <p className="text-sm text-muted-foreground mt-1">
                {error instanceof Error ? error.message : 'Unknown error'}
              </p>
            </Card>
          )}
          {isLoading ? (
            <div className="text-center py-12 text-muted-foreground">
              Loading rules...
            </div>
          ) : filteredRules.length === 0 ? (
            <Card className="p-12 text-center">
              <Shield className="h-12 w-12 mx-auto text-muted-foreground/50 mb-4" />
              <h3 className="text-lg font-semibold mb-2">
                {searchQuery || categoryFilter !== 'all' || severityFilter !== 'all' 
                  ? 'No rules found' 
                  : 'No rules yet'}
              </h3>
              <p className="text-muted-foreground mb-4">
                {searchQuery || categoryFilter !== 'all' || severityFilter !== 'all'
                  ? 'Try adjusting your filters'
                  : 'Add your first WAF rule to get started'}
              </p>
              {!searchQuery && categoryFilter === 'all' && severityFilter === 'all' && (
                <Button onClick={() => setIsEditorOpen(true)}>
                  <Plus className="h-4 w-4 mr-1" />
                  Add Rule
                </Button>
              )}
            </Card>
          ) : (
            <>
              <p className="text-sm text-muted-foreground">
                Showing {filteredRules.length} of {rules.length} rules
              </p>
              {filteredRules.map((rule) => (
                <RuleCard
                  key={rule.id}
                  rule={rule}
                  onEdit={() => handleEdit(rule)}
                  onDelete={() => handleDelete(rule.id)}
                />
              ))}
            </>
          )}
        </div>
      </main>

      {/* Rule Editor Modal */}
      <RuleEditor
        isOpen={isEditorOpen}
        onClose={handleEditorClose}
        rule={editingRule}
      />
    </div>
  )
}
