# Notification Fix - RLS Policy Issue

## Problem
Notifications are not being created because of Row Level Security (RLS) policies. The current policy only allows users to create notifications for themselves (`user_id = auth.uid()`), but when a worker cancels a booking or changes status, they need to create notifications for the **client** (different user).

## Solution

You have **TWO options**:

### Option 1: Simple RLS Policy Update (Recommended for quick fix)
Run `fix_notifications_rls_simple.sql` in your Supabase SQL Editor.

This updates the RLS policy to allow any authenticated user to create notifications for any user.

**Pros:**
- ✅ Simple and fast
- ✅ Works immediately
- ✅ No code changes needed

**Cons:**
- ⚠️ Less secure (any authenticated user can create notifications)

### Option 2: Database Function (More Secure)
Run `fix_notifications_rls.sql` in your Supabase SQL Editor.

This creates a database function with `SECURITY DEFINER` that bypasses RLS safely.

**Pros:**
- ✅ More secure
- ✅ Better audit trail
- ✅ Can add validation/logging in the function

**Cons:**
- ⚠️ Slightly more complex

## Which Should You Use?

**For quick testing:** Use Option 1 (simple policy update)

**For production:** Use Option 2 (database function)

## Steps to Fix

1. **Open Supabase Dashboard** → SQL Editor

2. **Choose ONE of these files:**
   - `fix_notifications_rls_simple.sql` (simple, recommended first)
   - `fix_notifications_rls.sql` (more secure)

3. **Copy and paste** the SQL code into the SQL Editor

4. **Run** the SQL script

5. **Test** by having a worker cancel a booking or change status - the client should now receive notifications!

## Verification

After running the fix, check the console logs when a worker performs an action:
- You should see: `✅ Notification created successfully`
- You should NOT see: `❌ ERROR creating notification`

If you still see errors, check:
1. The notifications table exists
2. The RLS policies were updated correctly
3. The user is authenticated

## What Was Changed

### Code Changes (Already Done)
- ✅ Enhanced error logging in `NotificationService`
- ✅ Added fallback to direct insert if function doesn't exist
- ✅ All notification calls already in place

### Database Changes (YOU NEED TO RUN)
- ⚠️ Run one of the SQL fix files above

## Current Notification Coverage

All these actions should now send notifications:

✅ Worker cancels booking → Client notified
✅ Worker accepts booking → Client notified
✅ Worker declines booking → Client notified
✅ Worker suggests time → Client notified
✅ Worker starts navigation → Client notified
✅ Worker finishes job → Client notified
✅ Client cancels booking → Worker notified
✅ All booking status changes → Appropriate party notified


