-- ============================================================
-- COMPLETE FIX FOR NOTIFICATIONS RLS ISSUE
-- Run this ENTIRE script in Supabase SQL Editor
-- This will fix the notification policy completely
-- ============================================================

-- Step 1: Drop ALL existing insert policies (clean slate)
DROP POLICY IF EXISTS notifications_insert_own ON public.notifications;
DROP POLICY IF EXISTS notifications_insert_all ON public.notifications;

-- Step 2: Create a new policy that allows any authenticated user to insert notifications
CREATE POLICY notifications_insert_all 
ON public.notifications
FOR INSERT 
TO authenticated
WITH CHECK (true);

-- Step 3: Verify the policy was created
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'notifications_insert_all'
  ) THEN
    RAISE NOTICE '✅ SUCCESS: Policy notifications_insert_all created successfully!';
  ELSE
    RAISE EXCEPTION '❌ ERROR: Policy was not created!';
  END IF;
END $$;

-- Step 4: Show current policies (for verification)
SELECT 
  policyname,
  cmd as command,
  qual as using_expression,
  with_check as with_check_expression
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications'
  AND cmd = 'INSERT'
ORDER BY policyname;

-- Step 5: Test that the policy works (this should return 1 row)
SELECT COUNT(*) as insert_policies_count
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT';

-- ============================================================
-- EXPECTED RESULT:
-- You should see 1 row with:
--   policyname: notifications_insert_all
--   command: INSERT
--   with_check_expression: true
-- ============================================================

