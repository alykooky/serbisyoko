-- ============================================================
-- TEST NOTIFICATION FUNCTION
-- Run this to test if the notification function works
-- ============================================================

-- Test the function (replace 'YOUR_USER_ID' with an actual user ID from your users table)
-- You can get a user ID by running: SELECT id FROM auth.users LIMIT 1;

-- First, get a test user ID
SELECT 
  'Available User IDs for Testing:' as info,
  id::text as user_id,
  email
FROM auth.users 
LIMIT 5;

-- Then test the function with one of those IDs:
-- (Replace 'YOUR_USER_ID_HERE' with an actual UUID from above)
/*
SELECT create_notification(
  'YOUR_USER_ID_HERE'::uuid,  -- Replace with actual user ID
  'test_notification',
  'Test Notification',
  'This is a test notification to verify the function works!',
  NULL,
  NULL
);
*/

-- Check if any notifications were created
SELECT 
  id,
  user_id,
  type,
  title,
  message,
  created_at
FROM public.notifications
ORDER BY created_at DESC
LIMIT 5;

