import { useState, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { X, Plus, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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
import { api, Rule, CreateRuleData, VariableSpec } from '@/lib/api'

interface RuleEditorProps {
  isOpen: boolean
  onClose: () => void
  rule?: Rule | null
}

const OPERATORS = ['regex', 'contains', 'starts_with', 'ends_with', 'equals', 'libinjection_sqli', 'libinjection_xss']
const ACTIONS = ['deny', 'allow', 'log']
const SEVERITIES = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW']
const CATEGORIES = ['xss', 'sqli', 'lfi', 'rce', 'rfi', 'xxe', 'nosql', 'crlf', 'user-agent', 'custom']
const VARIABLE_TYPES = ['ARGS', 'ARGS_NAMES', 'BODY', 'HEADERS', 'COOKIE', 'COOKIE_NAMES', 'REQUEST_LINE', 'REQUEST_FILENAME', 'REQUEST_BASENAME']
const TRANSFORMS = ['none', 'url_decode', 'url_decode_uni', 'lowercase', 'uppercase', 'remove_nulls', 'replace_comments', 'compress_whitespace', 'hex_decode', 'trim']

export function RuleEditor({ isOpen, onClose, rule }: RuleEditorProps) {
  const queryClient = useQueryClient()
  const isEditing = !!rule

  const [formData, setFormData] = useState<{
    id: number
    name: string
    msg: string
    pattern: string
    operator: string
    action: string
    severity: string
    category: string
    paranoia_level: number
    score: number
    default_score: number
    variables: VariableSpec[]
    transforms: string[]
    tags: string[]
  }>({
    id: 0,
    name: '',
    msg: '',
    pattern: '',
    operator: 'regex',
    action: 'deny',
    severity: 'MEDIUM',
    category: 'custom',
    paranoia_level: 1,
    score: 1,
    default_score: 1,
    variables: [{ type: 'ARGS' }],
    transforms: [],
    tags: [],
  })

  const [newTag, setNewTag] = useState('')

  useEffect(() => {
    if (rule) {
      setFormData({
        id: rule.id,
        name: rule.name || '',
        msg: rule.msg,
        pattern: rule.pattern || '',
        operator: rule.operator || 'regex',
        action: rule.action,
        severity: rule.severity || 'MEDIUM',
        category: rule.category || 'custom',
        paranoia_level: rule.paranoia_level || 1,
        score: rule.score ?? rule.default_score,
        default_score: rule.default_score,
        variables: rule.variables || [{ type: 'ARGS' }],
        transforms: rule.transforms || [],
        tags: rule.tags || [],
      })
    } else {
      // Generate new ID
      setFormData(prev => ({
        ...prev,
        id: Math.floor(Math.random() * 900000) + 100000,
        name: '',
        msg: '',
        pattern: '',
        operator: 'regex',
        action: 'deny',
        severity: 'MEDIUM',
        category: 'custom',
        paranoia_level: 1,
        score: 1,
        default_score: 1,
        variables: [{ type: 'ARGS' }],
        transforms: [],
        tags: [],
      }))
    }
  }, [rule, isOpen])

  const createMutation = useMutation({
    mutationFn: (data: CreateRuleData) => api.createRule(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rules'] })
      toast.success('Rule created')
      onClose()
    },
    onError: (error: Error) => {
      toast.error(`Failed to create rule: ${error.message}`)
    },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<CreateRuleData> }) =>
      api.updateRule(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rules'] })
      toast.success('Rule updated')
      onClose()
    },
    onError: (error: Error) => {
      toast.error(`Failed to update rule: ${error.message}`)
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    const data: CreateRuleData = {
      id: formData.id,
      name: formData.name || undefined,
      msg: formData.msg,
      pattern: formData.pattern || undefined,
      operator: formData.operator,
      action: formData.action,
      severity: formData.severity,
      category: formData.category,
      paranoia_level: formData.paranoia_level,
      score: formData.score !== formData.default_score ? formData.score : undefined,
      default_score: formData.default_score,
      variables: formData.variables.length > 0 ? formData.variables : undefined,
      transforms: formData.transforms.length > 0 ? formData.transforms : undefined,
      tags: formData.tags.length > 0 ? formData.tags : undefined,
    }

    if (isEditing) {
      updateMutation.mutate({ id: formData.id, data })
    } else {
      createMutation.mutate(data)
    }
  }

  const addVariable = () => {
    setFormData(prev => ({
      ...prev,
      variables: [...prev.variables, { type: 'ARGS' }],
    }))
  }

  const removeVariable = (index: number) => {
    setFormData(prev => ({
      ...prev,
      variables: prev.variables.filter((_, i) => i !== index),
    }))
  }

  const updateVariable = (index: number, type: string) => {
    setFormData(prev => ({
      ...prev,
      variables: prev.variables.map((v, i) => (i === index ? { type } : v)),
    }))
  }

  const toggleTransform = (transform: string) => {
    setFormData(prev => ({
      ...prev,
      transforms: prev.transforms.includes(transform)
        ? prev.transforms.filter(t => t !== transform)
        : [...prev.transforms, transform],
    }))
  }

  const addTag = () => {
    if (newTag && !formData.tags.includes(newTag)) {
      setFormData(prev => ({
        ...prev,
        tags: [...prev.tags, newTag],
      }))
      setNewTag('')
    }
  }

  const removeTag = (tag: string) => {
    setFormData(prev => ({
      ...prev,
      tags: prev.tags.filter(t => t !== tag),
    }))
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEditing ? 'Edit Rule' : 'Create New Rule'}</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Basic Info */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="id">Rule ID</Label>
              <Input
                id="id"
                type="number"
                value={formData.id}
                onChange={(e) => setFormData(prev => ({ ...prev, id: parseInt(e.target.value) || 0 }))}
                disabled={isEditing}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="name">Name</Label>
              <Input
                id="name"
                value={formData.name}
                onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                placeholder="Rule name"
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="msg">Message *</Label>
            <Input
              id="msg"
              value={formData.msg}
              onChange={(e) => setFormData(prev => ({ ...prev, msg: e.target.value }))}
              placeholder="Alert message when rule matches"
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="pattern">Pattern</Label>
            <Input
              id="pattern"
              value={formData.pattern}
              onChange={(e) => setFormData(prev => ({ ...prev, pattern: e.target.value }))}
              placeholder="Regex or match pattern"
              className="font-mono text-sm"
            />
          </div>

          {/* Rule Settings */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="space-y-2">
              <Label>Operator</Label>
              <Select
                value={formData.operator}
                onValueChange={(value) => setFormData(prev => ({ ...prev, operator: value }))}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {OPERATORS.map(op => (
                    <SelectItem key={op} value={op}>{op}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Action</Label>
              <Select
                value={formData.action}
                onValueChange={(value) => setFormData(prev => ({ ...prev, action: value }))}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ACTIONS.map(action => (
                    <SelectItem key={action} value={action}>{action}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Severity</Label>
              <Select
                value={formData.severity}
                onValueChange={(value) => setFormData(prev => ({ ...prev, severity: value }))}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {SEVERITIES.map(sev => (
                    <SelectItem key={sev} value={sev}>{sev}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Category</Label>
              <Select
                value={formData.category}
                onValueChange={(value) => setFormData(prev => ({ ...prev, category: value }))}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CATEGORIES.map(cat => (
                    <SelectItem key={cat} value={cat}>{cat}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Scoring */}
          <div className="grid grid-cols-3 gap-4">
            <div className="space-y-2">
              <Label htmlFor="score">Score</Label>
              <Input
                id="score"
                type="number"
                min="0"
                value={formData.score}
                onChange={(e) => setFormData(prev => ({ ...prev, score: parseInt(e.target.value) || 0 }))}
              />
              <p className="text-xs text-muted-foreground">Points added when matched</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="default_score">Default Score</Label>
              <Input
                id="default_score"
                type="number"
                min="0"
                value={formData.default_score}
                onChange={(e) => setFormData(prev => ({ ...prev, default_score: parseInt(e.target.value) || 1 }))}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="paranoia_level">Paranoia Level</Label>
              <Input
                id="paranoia_level"
                type="number"
                min="1"
                max="4"
                value={formData.paranoia_level}
                onChange={(e) => setFormData(prev => ({ ...prev, paranoia_level: parseInt(e.target.value) || 1 }))}
              />
            </div>
          </div>

          {/* Variables */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label>Variables</Label>
              <Button type="button" variant="outline" size="sm" onClick={addVariable}>
                <Plus className="h-3 w-3 mr-1" />
                Add
              </Button>
            </div>
            <div className="space-y-2">
              {formData.variables.map((variable, index) => (
                <div key={index} className="flex items-center gap-2">
                  <Select
                    value={variable.type}
                    onValueChange={(value) => updateVariable(index, value)}
                  >
                    <SelectTrigger className="flex-1">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {VARIABLE_TYPES.map(type => (
                        <SelectItem key={type} value={type}>{type}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={() => removeVariable(index)}
                    disabled={formData.variables.length === 1}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              ))}
            </div>
          </div>

          {/* Transforms */}
          <div className="space-y-2">
            <Label>Transforms</Label>
            <div className="flex flex-wrap gap-2">
              {TRANSFORMS.map(transform => (
                <Button
                  key={transform}
                  type="button"
                  variant={formData.transforms.includes(transform) ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => toggleTransform(transform)}
                >
                  {transform}
                </Button>
              ))}
            </div>
          </div>

          {/* Tags */}
          <div className="space-y-2">
            <Label>Tags</Label>
            <div className="flex gap-2">
              <Input
                value={newTag}
                onChange={(e) => setNewTag(e.target.value)}
                placeholder="Add tag"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault()
                    addTag()
                  }
                }}
              />
              <Button type="button" variant="outline" onClick={addTag}>
                <Plus className="h-4 w-4" />
              </Button>
            </div>
            {formData.tags.length > 0 && (
              <div className="flex flex-wrap gap-2 mt-2">
                {formData.tags.map(tag => (
                  <span
                    key={tag}
                    className="inline-flex items-center gap-1 px-2 py-1 bg-secondary rounded text-sm"
                  >
                    {tag}
                    <button
                      type="button"
                      onClick={() => removeTag(tag)}
                      className="hover:text-destructive"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="flex justify-end gap-2 pt-4 border-t">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={createMutation.isPending || updateMutation.isPending}
            >
              {createMutation.isPending || updateMutation.isPending
                ? 'Saving...'
                : isEditing
                ? 'Update Rule'
                : 'Create Rule'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
