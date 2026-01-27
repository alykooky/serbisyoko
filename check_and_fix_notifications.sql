-- ============================================================
-- CHECK AND FIX NOTIFICATIONS RLS - COMPLETE SOLUTION
-- Run this ENTIRE script in Supabase SQL Editor
-- ============================================================

-- STEP 1: Check current policies
SELECT 
  policyname,
  cmd as command,
  CASE 
    WHEN cmd = 'INSERT' THEN 'Creating notifications'
    WHEN cmd = 'SELECT' THEN 'Reading notifications'
    WHEN cmd = 'UPDATE' THEN 'Updating notifications'
    WHEN cmd = 'DELETE' THEN 'Deleting notifications'
  END as purpose
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications'
ORDER BY cmd, policyname;

-- STEP 2: Drop ALL existing INSERT policies (start fresh)
DROP POLICY IF EXISTS notifications_insert_own ON public.notifications;
DROP POLICY IF EXISTS notifications_insert_all ON public.notifications;

-- STEP 3: Create the new permissive policy
CREATE POLICY notifications_insert_all 
ON public.notifications
FOR INSERT 
TO authenticated
WITH CHECK (true);

-- STEP 4: Verify the new policy was created
SELECT 
  policyname,
  cmd as command,
  permissive,
  roles,
  CASE 
    WHEN with_check = 'true' THEN '✅ Allows all authenticated users to create notifications'
    ELSE '❌ Policy check: ' || with_check::text
  END as status
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications'
  AND cmd = 'INSERT';

-- STEP 5: Test query (should return 1 row)
SELECT 
  COUNT(*) as insert_policies,
  CASE 
    WHEN COUNT(*) = 1 THEN '✅ SUCCESS: Policy is correctly configured!'
    WHEN COUNT(*) = 0 THEN '❌ ERROR: No insert policy found!'
    ELSE '⚠️ WARNING: Multiple insert policies found!'
  END as result
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT';

-- ============================================================
-- EXPECTED RESULT AFTER RUNNING:
-- You should see:
--   1. A list of all current policies
--   2. A row showing: notifications_insert_all | INSERT | PERMISSIVE | {authenticated}
--   3. insert_policies: 1 | ✅ SUCCESS: Policy is correctly configured!
-- ============================================================

