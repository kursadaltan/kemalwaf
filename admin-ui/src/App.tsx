import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Toaster } from '@/components/ui/sonner'
import { api } from '@/lib/api'
import { SetupPage } from '@/pages/SetupPage'
import { LoginPage } from '@/pages/LoginPage'
import { DashboardPage } from '@/pages/DashboardPage'
import { LoadingScreen } from '@/components/LoadingScreen'

function AppRoutes() {
  // Check setup status
  const { data: setupStatus, isLoading: isSetupLoading } = useQuery({
    queryKey: ['setupStatus'],
    queryFn: api.getSetupStatus,
    retry: false,
  })

  // Check if user is authenticated
  const { data: user, isLoading: isAuthLoading } = useQuery({
    queryKey: ['me'],
    queryFn: api.getMe,
    retry: false,
    enabled: setupStatus?.setup_required === false,
  })

  if (isSetupLoading) {
    return <LoadingScreen message="Checking system status..." />
  }

  // If setup is required, show setup page
  if (setupStatus?.setup_required) {
    return (
      <Routes>
        <Route path="/setup" element={<SetupPage />} />
        <Route path="*" element={<Navigate to="/setup" replace />} />
      </Routes>
    )
  }

  if (isAuthLoading) {
    return <LoadingScreen message="Authenticating..." />
  }

  // If not authenticated, show login page
  if (!user) {
    return (
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    )
  }

  // Authenticated user routes
  return (
    <Routes>
      <Route path="/" element={<DashboardPage />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

function App() {
  return (
    <BrowserRouter>
      <AppRoutes />
      <Toaster position="top-right" />
    </BrowserRouter>
  )
}

export default App

