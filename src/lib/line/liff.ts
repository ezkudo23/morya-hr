import liff from '@line/liff'

let isInitialized = false

export async function initLiff(): Promise<void> {
  if (isInitialized) return

  await liff.init({
      liffId: process.env.NEXT_PUBLIC_LIFF_ID || '2009898155-F3QN9nis',
  })

  isInitialized = true
}

export async function getLiffProfile() {
  await initLiff()

  if (!liff.isLoggedIn()) {
    // เฉพาะใน LINE client เท่านั้นถึงจะ login
    if (liff.isInClient()) {
      liff.login()
    }
    return null
  }

  const profile = await liff.getProfile()
  const accessToken = liff.getAccessToken()

  return {
    userId: profile.userId,
    displayName: profile.displayName,
    pictureUrl: profile.pictureUrl,
    accessToken,
  }
}

export async function liffLogout(): Promise<void> {
  await initLiff()
  liff.logout()
}

export function isInLiff(): boolean {
  return liff.isInClient()
}