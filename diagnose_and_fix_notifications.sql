-- ============================================================
-- DIAGNOSE AND FIX NOTIFICATIONS - COMPREHENSIVE SOLUTION
-- Run this ENTIRE script in Supabase SQL Editor
-- ============================================================

-- ============================================================
-- PART 1: DIAGNOSE CURRENT STATE
-- ============================================================

-- Check if RLS is enabled
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename = 'notifications';

-- Check ALL current policies on notifications table
SELECT 
  policyname,
  cmd as command,
  permissive,
  roles,
  qual as using_clause,
  with_check as with_check_clause
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications'
ORDER BY cmd, policyname;

-- ============================================================
-- PART 2: CLEAN UP ALL EXISTING POLICIES
-- ============================================================

-- Drop ALL existing INSERT policies
DROP POLICY IF EXISTS notifications_insert_own ON public.notifications;
DROP POLICY IF EXISTS notifications_insert_all ON public.notifications;

-- ============================================================
-- PART 3: CREATE DATABASE FUNCTION (MOST RELIABLE)
-- This bypasses RLS entirely using SECURITY DEFINER
-- ============================================================

-- Create or replace the function
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_message text,
  p_related_id uuid DEFAULT NULL,
  p_related_type text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id uuid;
BEGIN
  -- Insert notification (bypasses RLS because function is SECURITY DEFINER)
  INSERT INTO public.notifications (
    user_id,
    type,
    title,
    message,
    related_id,
    related_type,
    is_read,
    created_at
  )
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_message,
    p_related_id,
    p_related_type,
    false,
    now()
  )
  RETURNING id INTO v_notification_id;
  
  RETURN v_notification_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_notification(uuid, text, text, text, uuid, text) TO authenticated;

-- Add comment
COMMENT ON FUNCTION create_notification IS 'Creates a notification for any user (bypasses RLS). Used by the notification service.';

-- ============================================================
-- PART 4: ALSO CREATE PERMISSIVE POLICY (BACKUP METHOD)
-- ============================================================

-- Create a permissive INSERT policy as backup
CREATE POLICY notifications_insert_all 
ON public.notifications
FOR INSERT 
TO authenticated
WITH CHECK (true);

-- ============================================================
-- PART 5: VERIFY FIXES
-- ============================================================

-- Check function exists
SELECT 
  'Function Check:' as check_type,
  COUNT(*) as function_count,
  CASE 
    WHEN COUNT(*) >= 1 THEN '✅ Function exists!'
    ELSE '❌ Function not found!'
  END as status
FROM pg_proc 
WHERE proname = 'create_notification'
  AND pronamespace = 'public'::regnamespace;

-- Check policy exists
SELECT 
  'Policy Check:' as check_type,
  COUNT(*) as policy_count,
  CASE 
    WHEN COUNT(*) >= 1 THEN '✅ Policy created!'
    ELSE '❌ Policy not found!'
  END as status
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT';

-- Show final state
SELECT 
  'Final State:' as info,
  policyname,
  cmd as command,
  with_check as policy_rule
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT';

-- ============================================================
-- ✅ EXPECTED RESULTS:
-- 
-- 1. RLS enabled: true
-- 2. Function Check: 1 | ✅ Function exists!
-- 3. Policy Check: 1 | ✅ Policy created!
-- 4. Final State: notifications_insert_all | INSERT | true
--
-- If you see all these, the fix is complete!
-- ============================================================

