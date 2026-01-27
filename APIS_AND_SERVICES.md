# APIs and Services Used in SerbisyoKo Application

## Overview
This document lists all the external APIs and services used in the SerbisyoKo application.

---

## 1. **Supabase** - Backend as a Service (BaaS)
**Purpose:** Primary database and backend service

**Used for:**
- User authentication and authorization
- Database operations (PostgreSQL)
- Real-time subscriptions (websockets)
- File storage
- Row Level Security (RLS) policies

**Package:** `supabase_flutter`

**Usage Examples:**
- `Supabase.instance.client.from('users').select()`
- `Supabase.instance.client.auth.currentUser`
- Real-time channels for live updates

---

## 2. **Nominatim API (OpenStreetMap)** - Geocoding Service
**Purpose:** Reverse geocoding and location search

**Base URL:** `https://nominatim.openstreetmap.org`

### 2.1 Reverse Geocoding (Coordinates → Address)
**Endpoint:** `/reverse`
**Usage:** Convert latitude/longitude coordinates to human-readable addresses

**Example:**
```dart
'https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1'
```

**Used in:**
- `lib/widgets/location_picker.dart` - Getting exact location addresses
- `lib/Dashboard.dart` - Updating user location with full address
- `lib/screens/match_map_page.dart` - Displaying location addresses

**Features:**
- Returns complete address with:
  - House/Building number
  - Street name
  - Neighborhood/Village/Suburb
  - City/Town/Municipality
  - State/Province
  - Country

### 2.2 Location Search (Query → Coordinates)
**Endpoint:** `/search`
**Usage:** Search for locations by name/address

**Example:**
```dart
'https://nominatim.openstreetmap.org/search?format=json&q=${query}&limit=5&addressdetails=1'
```

**Used in:**
- Location picker search functionality
- Finding locations by name

**Rate Limits:**
- Free tier: 1 request per second
- Requires proper User-Agent header

---

## 3. **OpenStreetMap Tile Service** - Map Tiles
**Purpose:** Display map tiles in the application

**Base URL:** `https://tile.openstreetmap.org` or `https://{s}.tile.openstreetmap.org`

**Usage:**
- Map display in location picker
- Map display in booking details
- Map display in navigation screens

**Example:**
```dart
urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
```

**Used in:**
- `lib/widgets/location_picker.dart`
- `lib/screens/match_map_page.dart`
- `lib/booking_detail_screen.dart`
- `lib/live_navigation_screen.dart`

**Note:** This is a free service provided by OpenStreetMap for displaying map tiles.

---

## 4. **Geolocator** - GPS Location Service
**Purpose:** Access device GPS/location services

**Package:** `geolocator`

**Features:**
- Get current device location
- Request location permissions
- Different accuracy levels (high, best, medium)
- Check if location services are enabled

**Usage Examples:**
- `Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)`
- `Geolocator.checkPermission()`
- `Geolocator.isLocationServiceEnabled()`

**Used in:**
- All location-related features
- Fetching user's current location
- Worker location tracking

---

## 5. **FlutterMap** - Map Widget
**Purpose:** Interactive map display component

**Package:** `flutter_map`

**Features:**
- Interactive map with markers
- Custom map controllers
- Routing and navigation
- Multiple tile providers support

**Used with:**
- OpenStreetMap tiles
- Custom markers for locations
- Route visualization

---

## Summary of External Services

| Service | Type | Purpose | Free/Paid |
|---------|------|---------|-----------|
| **Supabase** | Backend/Database | Primary backend service | Free tier available |
| **Nominatim API** | Geocoding | Address lookup and search | Free (rate limited) |
| **OpenStreetMap Tiles** | Map Tiles | Map display | Free |
| **Geolocator** | Device Service | GPS access | Free (device service) |
| **FlutterMap** | Library | Map widget | Free (open source) |

---

## API Configuration Notes

### User-Agent Header
Nominatim API requires a proper User-Agent header:
```dart
headers: {
  'User-Agent': 'SerbisyoKoApp/1.0 (contact@serbisyo.com)',
}
```

### Rate Limits
- **Nominatim:** 1 request per second (free tier)
- **OpenStreetMap Tiles:** Should be used responsibly
- **Supabase:** Based on your plan limits

### Error Handling
All API calls include proper error handling and fallback mechanisms to ensure the app continues working even if external services are unavailable.

---

## Authentication & Security

### Supabase
- Uses Row Level Security (RLS) policies
- JWT-based authentication
- Secure API keys stored in environment

### Location Services
- Requires user permission (handled via Geolocator)
- Permissions requested at runtime
- Graceful handling of denied permissions

---

## Dependencies (from pubspec.yaml)
```yaml
- supabase_flutter: ^2.x.x
- geolocator: ^10.x.x
- flutter_map: ^6.x.x
- latlong2: ^0.8.x
- http: ^1.x.x (for Nominatim API calls)
```

