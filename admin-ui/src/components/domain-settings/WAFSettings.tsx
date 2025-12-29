import { useState } from 'react'
import { Shield, Code } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { DomainRulesConfig } from '@/components/DomainRulesConfig'
import { CustomRulesSettings } from './CustomRulesSettings'

interface WAFSettingsProps {
  domain: string
}

type TabType = 'global' | 'custom'

export function WAFSettings({ domain }: WAFSettingsProps) {
  const [activeTab, setActiveTab] = useState<TabType>('global')

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>WAF Configuration</CardTitle>
        </CardHeader>
        <CardContent>
          {/* Tabs */}
          <div className="flex gap-2 border-b mb-6">
            <Button
              variant={activeTab === 'global' ? 'default' : 'ghost'}
              onClick={() => setActiveTab('global')}
              className="rounded-b-none"
            >
              <Shield className="h-4 w-4 mr-2" />
              Global Rules
            </Button>
            <Button
              variant={activeTab === 'custom' ? 'default' : 'ghost'}
              onClick={() => setActiveTab('custom')}
              className="rounded-b-none"
            >
              <Code className="h-4 w-4 mr-2" />
              Custom Rules
            </Button>
          </div>

          {/* Tab Content */}
          {activeTab === 'global' && <DomainRulesConfig domain={domain} />}
          {activeTab === 'custom' && <CustomRulesSettings domain={domain} />}
        </CardContent>
      </Card>
    </div>
  )
}
