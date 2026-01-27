-- ============================================================
-- FIX NOTIFICATIONS RLS - Simple Policy Update
-- Run this in your Supabase SQL Editor to fix notification issues
-- This allows any authenticated user to create notifications for any user
-- ============================================================

-- First, check if the restrictive policy exists and drop it
DROP POLICY IF EXISTS notifications_insert_own ON public.notifications;

-- Drop the new policy if it already exists (in case you're re-running this)
DROP POLICY IF EXISTS notifications_insert_all ON public.notifications;

-- Create a new policy that allows authenticated users to create notifications for any user
CREATE POLICY notifications_insert_all ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (true); -- Allow any authenticated user to create notifications

-- Verify the policy was created
SELECT 
  schemaname, 
  tablename, 
  policyname, 
  permissive,
  roles,
  cmd
FROM pg_policies 
WHERE tablename = 'notifications' 
  AND policyname = 'notifications_insert_all';

-- You should see a row with policyname = 'notifications_insert_all'
-- If you see it, the fix is successful!

-- ============================================================
-- ALTERNATIVE: Use Database Function (More Secure)
-- If you prefer a more secure approach, use fix_notifications_rls.sql instead
-- ============================================================

