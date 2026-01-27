-- ============================================================
-- FINAL FIX FOR NOTIFICATIONS - Run This Now!
-- Copy this ENTIRE file and run in Supabase SQL Editor
-- ============================================================

-- STEP 1: Remove the restrictive INSERT policy (this is blocking notifications)
DROP POLICY IF EXISTS notifications_insert_own ON public.notifications;

-- STEP 2: Remove any other INSERT policies that might conflict
DROP POLICY IF EXISTS notifications_insert_all ON public.notifications;

-- STEP 3: Create a new policy that allows any authenticated user to create notifications
CREATE POLICY notifications_insert_all 
ON public.notifications
FOR INSERT 
TO authenticated
WITH CHECK (true);

-- STEP 4: Verify it worked (should show 1 row)
SELECT 
  'Policy Check:' as check_type,
  COUNT(*) as policy_count,
  CASE 
    WHEN COUNT(*) >= 1 THEN '✅ SUCCESS! Policy created correctly.'
    ELSE '❌ ERROR: Policy not found!'
  END as status
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT'
  AND with_check = 'true';

-- STEP 5: Show the actual policy details
SELECT 
  policyname,
  cmd as command,
  permissive,
  roles,
  with_check as policy_rule
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT';

-- ============================================================
-- ✅ EXPECTED RESULT:
-- 
-- You should see:
--   1. Policy Check: 1 | ✅ SUCCESS! Policy created correctly.
--   2. One row showing:
--      - policyname: notifications_insert_all
--      - command: INSERT
--      - permissive: PERMISSIVE
--      - roles: {authenticated}
--      - policy_rule: true
--
-- If you see this, the fix worked! Test notifications now.
-- ============================================================

