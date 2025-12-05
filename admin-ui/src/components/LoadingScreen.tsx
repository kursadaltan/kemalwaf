import { Shield, Loader2 } from 'lucide-react'

interface LoadingScreenProps {
  message?: string
}

export function LoadingScreen({ message = 'Loading...' }: LoadingScreenProps) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-background">
      <div className="flex flex-col items-center gap-6 animate-in">
        <div className="relative">
          <Shield className="h-16 w-16 text-primary" />
          <Loader2 className="h-6 w-6 text-primary animate-spin absolute -bottom-1 -right-1" />
        </div>
        <div className="text-center">
          <h1 className="text-2xl font-bold text-foreground">Kemal WAF</h1>
          <p className="text-muted-foreground mt-1">{message}</p>
        </div>
      </div>
    </div>
  )
}

