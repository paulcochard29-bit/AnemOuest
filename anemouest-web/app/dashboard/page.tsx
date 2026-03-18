'use client'

import { Suspense } from 'react'
import { DashboardBuilder } from './DashboardBuilder'

export default function DashboardPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-[#f2f2f7]">
        <div className="w-6 h-6 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
      </div>
    }>
      <DashboardBuilder />
    </Suspense>
  )
}
