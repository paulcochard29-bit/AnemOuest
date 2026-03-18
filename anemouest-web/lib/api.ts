export const API = process.env.NEXT_PUBLIC_API_URL || 'https://api.levent.live/api'
export const API_KEY = process.env.NEXT_PUBLIC_API_KEY || 'lv_LE0-nqlL3Ovud7X_Dnm4JuUC7DcJejs5'

const apiHeaders: HeadersInit = { 'X-Api-Key': API_KEY }

/** fetch wrapper that automatically adds the API key header */
export function apiFetch(url: string, opts?: RequestInit): Promise<Response> {
  const merged = {
    ...opts,
    headers: { ...apiHeaders, ...(opts?.headers as Record<string, string> || {}) },
  }
  return fetch(url, merged)
}
