# Dynamic Availability Schedule Fix

## Problem
The worker availability system was not working dynamically. Workers could set their availability schedule (e.g., Monday 14:09 - 14:26), but even after the end time passed (e.g., at 14:27), they were still showing as available and active in the matching system.

## Root Cause
The system was only checking the `availability_status` field in `worker_profiles` (ON/OFF), but was not checking the actual schedule windows from the `worker_availability` table to determine if the worker should be available based on the current time.

## Solution Implemented

### 1. **Dynamic Schedule Checking in Matching Algorithm** (`lib/services/advanced_matching_service.dart`)
   - Added `_checkAvailabilitySchedules()` method that fetches each worker's schedule from `worker_availability` table
   - Added `_isWorkerAvailableNow()` helper method that checks if current time is within any active schedule window
   - Updated `_fetchCandidates()` to check schedules after loading workers and filter out workers who are outside their schedule windows
   - Workers are now filtered before scoring, so they won't appear in matching results if outside their schedule

### 2. **Automatic Status Updates** (`lib/ServiceProviderDashboard.dart`)
   - Added `_checkScheduleAvailability()` method that checks if worker should be available based on current time and schedule
   - Added periodic timer (`_scheduleCheckTimer`) that runs every 30 seconds to check and automatically update availability status
   - When schedule window expires, the worker's `availability_status` is automatically set to 'OFF' in the database
   - When schedule window starts, the worker's `availability_status` is automatically set to 'ON' (if it was previously ON)

### 3. **Prevent Manual Override Outside Schedule**
   - Updated `_toggleAvailability()` to prevent workers from manually turning availability ON if they are outside their schedule window
   - Workers can still manually turn availability OFF at any time
   - When trying to turn ON outside schedule, shows an error message: "Cannot turn ON: You are outside your scheduled availability window."

### 4. **Enhanced Debug Logging**
   - Added comprehensive debug logging to track:
     - When workers are filtered out due to schedule
     - Current time vs schedule window comparisons
     - Automatic status updates
     - Schedule check results

### 5. **Model Updates** (`lib/models/worker_profile.dart`)
   - Added `isCurrentlyAvailable` field to `WorkerProfile` class to track real-time availability based on schedule
   - This field is set dynamically during matching and is used for availability scoring

## How It Works

1. **During Matching:**
   - When a client searches for workers, the system:
     1. Fetches candidate workers based on skills and location
     2. Checks each worker's schedule from `worker_availability` table
     3. Determines if current time is within their active schedule windows
     4. Filters out workers who are outside their schedule
     5. Only shows workers who are currently available based on schedule

2. **Worker Dashboard:**
   - Every 30 seconds, the dashboard checks:
     - Current day of week (Monday=1, Sunday=7)
     - Current time (in seconds since midnight)
     - Worker's schedule windows for today
     - If current time is within any active schedule window
   - If status doesn't match schedule:
     - Automatically updates `worker_profiles.availability_status` to match schedule
     - Updates UI to reflect new status
     - Starts/stops heartbeat accordingly

3. **Schedule Window Logic:**
   - Normal range (e.g., 09:00 - 17:00): Available if current time >= start AND current time < end
   - Overnight range (e.g., 22:00 - 06:00): Available if current time >= start OR current time < end
   - If no schedule is set: Falls back to manual `availability_status` setting

## Testing

To test the fix:
1. Set a worker's availability schedule (e.g., Monday 14:09 - 14:26)
2. Ensure the worker's status is ON
3. Wait until after the end time (e.g., 14:27)
4. The worker should automatically:
   - Have their status set to OFF in the database
   - Not appear in matching results
   - Show as unavailable in their dashboard
5. When the schedule window starts again, the status should automatically turn ON (if it was previously ON)

## Files Modified

1. `lib/services/advanced_matching_service.dart`
   - Added schedule checking logic
   - Added worker filtering based on schedule

2. `lib/ServiceProviderDashboard.dart`
   - Added periodic schedule checking timer
   - Added automatic status updates
   - Added prevention of manual override outside schedule

3. `lib/models/worker_profile.dart`
   - Added `isCurrentlyAvailable` field

## Database Schema

The fix uses the existing `worker_availability` table:
- `user_id`: Worker's user ID
- `weekday`: Day of week (1=Monday, 7=Sunday)
- `start_at`: Start time (HH:MM:SS format)
- `end_at`: End time (HH:MM:SS format)
- `is_active`: Whether this schedule slot is active

No database migrations are required - the fix uses existing schema.


