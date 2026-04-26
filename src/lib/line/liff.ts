import liff from '@line/liff'

let isInitialized = false

export async function initLiff(): Promise<void> {
  if (isInitialized) return

  await liff.init({
    liffId: process.env.NEXT_PUBLIC_LIFF_ID!,
  })

  isInitialized = true
}

export async function getLiffProfile() {
  await initLiff()

  if (!liff.isLoggedIn()) {
    liff.login()
    return null
  }

  const profile = await liff.getProfile()
  const idToken = liff.getIDToken()

  return {
    userId: profile.userId,
    displayName: profile.displayName,
    pictureUrl: profile.pictureUrl,
    idToken,
  }
}

export async function liffLogout(): Promise<void> {
  await initLiff()
  liff.logout()
}

export function isInLiff(): boolean {
  return liff.isInClient()
}