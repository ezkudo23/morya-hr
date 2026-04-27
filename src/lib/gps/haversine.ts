// Haversine formula — คำนวณระยะห่างระหว่าง 2 จุด GPS (เมตร)
export function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371000 // รัศมีโลก (เมตร)
  const φ1 = (lat1 * Math.PI) / 180
  const φ2 = (lat2 * Math.PI) / 180
  const Δφ = ((lat2 - lat1) * Math.PI) / 180
  const Δλ = ((lon2 - lon1) * Math.PI) / 180

  const a =
    Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
    Math.sin(Δλ / 2) * Math.sin(Δλ / 2)

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

// Cost centers GPS (ตาม MRD 7.3)
export const COST_CENTER_LOCATIONS = [
  {
    code: 'CC-HQ-WS',
    name: 'สำนักงานใหญ่ ขายส่ง',
    lat: 14.886239,
    lng: 103.492307,
  },
  {
    code: 'CC-01',
    name: 'สำนักงานใหญ่ ขายปลีก',
    lat: 14.8864189,
    lng: 103.4919395,
  },
  {
    code: 'CC-04',
    name: 'สาขา 4',
    lat: 14.8732376,
    lng: 103.5060382,
  },
]

export const GPS_RADIUS_METERS = 100 // ตาม MRD 7.3

export type NearestLocation = {
  code: string
  name: string
  distance: number
  isValid: boolean
}

// หา location ที่ใกล้ที่สุด + เช็คว่าอยู่ในรัศมีไหม
export function findNearestLocation(
  userLat: number,
  userLng: number
): NearestLocation {
  let nearest = {
    code: '',
    name: '',
    distance: Infinity,
    isValid: false,
  }

  for (const loc of COST_CENTER_LOCATIONS) {
    const distance = haversineDistance(userLat, userLng, loc.lat, loc.lng)
    if (distance < nearest.distance) {
      nearest = {
        code: loc.code,
        name: loc.name,
        distance: Math.round(distance),
        isValid: distance <= GPS_RADIUS_METERS,
      }
    }
  }

  return nearest
}

// ขอ GPS จาก browser
export async function getCurrentPosition(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('GPS ไม่รองรับบนอุปกรณ์นี้'))
      return
    }

    navigator.geolocation.getCurrentPosition(
      resolve,
      (error) => {
        switch (error.code) {
          case error.PERMISSION_DENIED:
            reject(new Error('กรุณาอนุญาต GPS เพื่อ check-in'))
            break
          case error.POSITION_UNAVAILABLE:
            reject(new Error('ไม่สามารถระบุตำแหน่งได้'))
            break
          case error.TIMEOUT:
            reject(new Error('GPS timeout — ลองใหม่อีกครั้ง'))
            break
          default:
            reject(new Error('GPS error'))
        }
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0,
      }
    )
  })
}