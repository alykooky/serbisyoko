# Booking Cancellation System

## Overview
A comprehensive cancellation system that protects both clients and workers while preventing abuse. The system includes different rules for different booking stages and automatic cleanup of stale bookings.

## Cancellation Rules

### 1. **Client Cancellation - Before Worker Accepts** ✅
**Status Flow:** `pending` → `cancelled_by_client`

- ✅ **No penalties** - Worker hasn't committed yet
- ✅ **No reason required** - Simple one-click cancellation
- ✅ **Instant notification** - Worker is notified immediately
- ✅ **Removed from worker's "Matched Jobs"** - Automatically filtered out

**Use Case:** Client changes their mind, found another worker, or no longer needs the service before any commitment is made.

### 2. **Client Cancellation - After Worker Accepts** ⚠️
**Status Flow:** `accepted` → `cancelled_by_client`

- ⚠️ **Requires reason** - Must select from predefined reasons
- ⚠️ **Confirmation dialog** - Double-check to prevent accidental cancellation
- ⚠️ **Cancellation limit** - Max 5 cancellations per month (configurable)
- ✅ **Worker notified** - Worker is informed of cancellation and reason

**Reasons Available:**
- Found another worker
- Service no longer needed
- Scheduling conflict
- Price concern
- Other (requires additional notes)

**Use Case:** Client needs to cancel after worker has already accepted and committed to the job.

### 3. **Worker Cancellation** 🔒
**Status:** `cancelled_by_worker`

- 🔒 **Always requires reason** - Workers must select from predefined reasons
- 🔒 **Cancellation logged** - All cancellations tracked for accountability
- 🔒 **Abuse prevention** - Excessive cancellations can reduce match priority

**Required Reasons:**
- Emergency
- Incomplete client information
- Safety concern
- Double booking (system issue)
- Other (requires additional notes)

**Use Case:** Worker encounters issues that prevent them from completing the service.

### 4. **Auto-Cancellation** 🤖

#### Case A: Worker Didn't Respond
- **Trigger:** Booking has been `pending` for more than 30 minutes (configurable)
- **Action:** Auto-cancel and notify client
- **Status:** `auto_cancelled_no_response`
- **Reason:** "Worker did not respond within X minutes"

#### Case B: Client Didn't Confirm
- **Trigger:** Booking has been `accepted` for more than 24 hours (configurable) without client confirmation
- **Action:** Auto-cancel and notify both parties
- **Status:** `auto_cancelled_unconfirmed`
- **Reason:** "Client did not confirm within X hours"

**Implementation:** Uses Supabase scheduled functions (pg_cron) or can be called via API endpoint.

## Database Schema

### Bookings Table Updates
```sql
ALTER TABLE public.bookings
ADD COLUMN cancelled_at timestamptz,
ADD COLUMN cancelled_by text, -- 'client', 'worker', or 'system'
ADD COLUMN cancellation_reason text,
ADD COLUMN cancellation_notes text;
```

### New Table: booking_cancellations
Tracks all cancellations for analytics and abuse prevention:
```sql
CREATE TABLE public.booking_cancellations (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    user_type text NOT NULL, -- 'client' or 'worker'
    booking_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamptz NOT NULL
);
```

## Files Created/Modified

### New Files:
1. **`lib/services/booking_cancellation_service.dart`**
   - Main service handling all cancellation logic
   - Methods for client/worker cancellations
   - Tracking and abuse prevention
   - Auto-cancellation functions

2. **`lib/widgets/cancellation_dialog.dart`**
   - Reusable dialog for cancellation
   - Different UI for clients vs workers
   - Reason selection and notes input

3. **`create_booking_cancellation_system.sql`**
   - Database migrations
   - SQL functions for auto-cancellation
   - Indexes and RLS policies

### Modified Files:
1. **`lib/my_bookings.dart`**
   - Updated `_cancelBooking()` to use new cancellation service
   - Added cancellation limit checking
   - Improved user feedback

2. **`lib/worker_bookings_history.dart`**
   - Updated `_declineBooking()` to use new cancellation service
   - Worker must provide reason
   - Cancellation tracking

## Setup Instructions

### 1. Run Database Migration
Execute `create_booking_cancellation_system.sql` in your Supabase SQL Editor to:
- Add cancellation fields to `bookings` table
- Create `booking_cancellations` tracking table
- Create SQL functions for auto-cancellation
- Set up indexes and RLS policies

### 2. Set Up Auto-Cancellation Jobs (Optional)

#### Option A: Using Supabase Edge Functions + Cron
Create a scheduled Edge Function that calls the auto-cancellation functions.

#### Option B: Using External Cron Job
Set up a cron job that calls your API endpoint to trigger auto-cancellation.

#### Option C: Manual Trigger
Call the functions manually via SQL:
```sql
-- Cancel unresponded bookings (older than 30 minutes)
SELECT auto_cancel_unresponded_bookings(30);

-- Cancel unconfirmed bookings (older than 24 hours)
SELECT auto_cancel_unconfirmed_bookings(24);
```

### 3. Configuration

You can customize the following values in `BookingCancellationService`:
- **Max cancellations per month:** Default 5 (configurable per user)
- **Auto-cancel threshold (worker response):** Default 30 minutes
- **Auto-cancel threshold (client confirmation):** Default 24 hours

## User Flows

### Client Cancellation Flow:
1. Client opens booking details
2. Taps "Cancel" button
3. System checks booking status:
   - **If pending:** Simple confirmation dialog (no reason needed)
   - **If accepted:** Shows reason selection dialog
4. System checks cancellation limit
5. If within limit: Cancellation proceeds
6. Booking status updated, notifications sent

### Worker Cancellation Flow:
1. Worker opens booking details
2. Taps "Cancel" button
3. System shows reason selection dialog (always required)
4. Worker selects reason and optionally adds notes
5. System checks cancellation limit
6. If within limit: Cancellation proceeds
7. Booking status updated, notifications sent, cancellation logged

## Abuse Prevention

### Cancellation Tracking
- All cancellations are logged in `booking_cancellations` table
- System tracks cancellation count per user (last 30 days)
- Default limit: 5 cancellations per month

### Consequences of Excessive Cancellations
- User gets warning when approaching limit
- Cancellations blocked when limit exceeded
- Can be extended to reduce match priority (future enhancement)

## Status Values

Valid booking statuses include:
- `pending` - Waiting for worker response
- `accepted` - Worker accepted, waiting for service
- `inprogress` - Service in progress
- `completed` - Service completed
- `cancelled_by_client` - Cancelled by client
- `cancelled_by_worker` - Cancelled by worker
- `auto_cancelled_no_response` - Auto-cancelled (worker didn't respond)
- `auto_cancelled_unconfirmed` - Auto-cancelled (client didn't confirm)
- `declined` - Worker declined (different from cancelled)

## Testing

### Test Cases:
1. ✅ Client cancels pending booking (no reason required)
2. ✅ Client cancels accepted booking (reason required)
3. ✅ Worker cancels booking (reason always required)
4. ✅ Cancellation limit enforcement
5. ✅ Notifications sent to all parties
6. ✅ Auto-cancellation for unresponded bookings
7. ✅ Auto-cancellation for unconfirmed bookings

## Future Enhancements

1. **Reduced Match Priority:** Workers/clients with high cancellation rates get lower priority in matching
2. **Cancellation Fees:** Optional penalty for late cancellations (if payment system is added)
3. **Cancellation Analytics:** Dashboard showing cancellation patterns
4. **Smart Rematching:** Automatically rematch auto-cancelled bookings
5. **Grace Period:** Allow cancellations within X hours after acceptance without penalty

## Notes

- **No Money Involved:** Since this is a third-party app without in-app payments, cancellation rules focus on preventing abuse and maintaining good user experience
- **Flexible Configuration:** All thresholds and limits can be adjusted via service methods
- **Scalable:** System designed to handle high volumes with proper indexing
- **Transparent:** Users are always informed about cancellation policies and limits


