# EVPair (formerly PS-EV)

A peer-to-peer marketplace where **home EV charger owners (hosts)** rent out
their private charger's free time slots to **EV car owners (drivers)**.

App id / bundle identifier: `com.evpairapp.evpair` (Flutter project - not
React Native/Expo, so there is no `app.json`/`app.config.js` to edit; the
bundle id lives in the native Android/iOS project folders that
`flutter create` generates, which aren't part of this `lib/`-only zip).

## Fixes in this version

### 1. Pick date / start time / end time buttons now match the "One-time" theme
These were plain grey `OutlinedButton`s. Replaced with the new
**`PsEvFilledButton`** widget (solid emerald background, white bold text,
rounded) - the same look as the "One-time" segmented-control tab.
(`theme/ps_ev_theme.dart`, used throughout `manage_charger_screen.dart`)

### 2. Registration now asks First name + Last name
`AuthService.register()` and `RegisterScreen` split the single "Full name"
field into separate **First name** / **Last name** fields.

### 3. Added a power tier above 50 kW
`kPowerOptions` in `state/app_state.dart` now includes `100` kW alongside
3.3 / 7.4 / 11 / 22 / 50.

### 4. Save Charger / Submit Top-Up now use the same green/white theme
Both now use `PsEvFilledButton` instead of the default `ElevatedButton`,
for full visual consistency with every other primary action.

### 5. Wallet "insufficient balance" bug - root cause found & fixed
The displayed total (rounded for display, e.g. "75 EGP") could be a tiny
fraction less than the *actual* floating-point total used in the
`balance >= total` comparison (e.g. 75.35), especially with per-kWh
pricing over odd slot durations. A driver with exactly 75 EGP would see
"insufficient balance" even though the number on screen matched their
balance exactly.

**Fix**: `PricingService.computeCost()` now rounds to a whole EGP amount
*once, centrally*, and that same rounded value is used everywhere - for
display, for the balance comparison, and for the amount actually held on
the `Booking`. I verified this eliminates the mismatch with a script
reproducing the exact scenario (see chat). Also bumped the demo's seeded
wallet balance from 500 → 3000 EGP, since multi-hour demo slots can
legitimately cost several hundred EGP and the old seed amount made
hitting "insufficient balance" (for real, non-buggy reasons) very likely.

### 6. Added location wasn't showing on the map
Root cause: `ChargerFormScreen` always created new chargers at one
hard-coded lat/lng, regardless of the Area the host selected or any map
link entered.

**Fix**: new `kAreaCoordinates` lookup table (approximate coordinates per
Area option) in `state/app_state.dart`, plus a `tryParseLatLngFromMapLink()`
regex parser in `charger_form_screen.dart` that extracts real coordinates
from a pasted Google Maps link (e.g.
`https://maps.google.com/?q=30.0131,31.4326`) when present. Priority:
parsed map-link coordinates → area lookup → fallback. Verified both
against real Google Maps link formats.

### 7. Host: distinguishing "Booked" vs "Charging" (running session)
New status pill factories `PsEvStatusPill.bookedAwaitingScan()` (amber -
confirmed, driver hasn't arrived/scanned yet) and `PsEvStatusPill.charging()`
(blue - session actively running). Now shown:
- On each charger card in **Host Home** (badge counts)
- In a new **"Active Bookings"** section on **Manage Charger**
- As an explicit pill on each card in **Host Scan / Active Sessions**

### 8. New driver tab: "My Bookings"
New `MyBookingsScreen` (reached via a header icon on Driver Home) lists
ALL of the driver's ongoing bookings - pending, booked/confirmed, and
actively charging - each with a status pill, charger name, time, held
amount, and a live duration timer while charging.

## On sharing files going forward
Since zip attachments aren't working on your end, please attach
individual `.dart` files directly (plain text uploads work fine, no size
issue there) - there's no strict file-count limit on my end, so send
whichever screens/services you're changing plus `pubspec.yaml` if
dependencies changed. I'll make targeted edits to just those files instead
of reconstructing the whole project.

## ⚠️ Admin is a demo-only bottom-nav tab — NOT for production
Remove `AdminHomeScreen` from `AppRoot`'s tabs before shipping; ship admin
tooling as its own separate, authenticated app.

## Still pending (per your note, not built yet)
- **Multiple cars per driver.** Currently `AppState.car` holds a single
  `CarProfile`. You asked me to remember this for a future message rather
  than build it now - it is NOT included in this version.

## Project structure

```
lib/
  state/app_state.dart        - AppRole, shared data, kPowerOptions (+100kW),
                                 kAreaCoordinates (NEW)
  services/
    auth_service.dart          - firstName/lastName registration
    pricing_service.dart       - computeCost() now rounds consistently (NEW fix)
    wallet_service.dart        - added seedBalance() for clean demo seeding
    booking_service.dart       - added ongoingForDriver/confirmedForHost/
                                  inProgressForHost (NEW)
    matching_service.dart

  theme/
    ps_ev_theme.dart            - added PsEvFilledButton (NEW),
                                   PsEvStatusPill.bookedAwaitingScan()/.charging()
    ps_ev_app_bar.dart

  screens/
    root/app_root.dart
    auth/register_screen.dart   - first/last name fields
    driver/
      driver_home_screen.dart    - added "My Bookings" header icon,
                                    map now centers on real charger positions
      my_bookings_screen.dart    - NEW
      car_setup_screen.dart, wallet_screen.dart, topup_screen.dart,
      topup_status_screen.dart, booking_request_screen.dart,
      booking_status_screen.dart
    host/
      charger_form_screen.dart   - map-link coordinate parsing (NEW),
                                    PsEvFilledButton for Save
      manage_charger_screen.dart - PsEvFilledButton for date/time pickers,
                                    new "Active Bookings" section (NEW)
      host_home_screen.dart      - Booked/Charging badges (NEW)
      host_scan_screen.dart      - explicit Booked/Charging pills (NEW)
    admin/admin_home_screen.dart

  models/
    enums.dart, charger_profile.dart, availability_slot.dart, booking.dart,
    car_profile.dart, wallet_transaction.dart

  main.dart                    - renamed app to EVPair, seeds 3000 EGP balance
```
