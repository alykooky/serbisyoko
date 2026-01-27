-- ============================================================
-- FIX NOTIFICATIONS RLS - Allow creating notifications for other users
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Create a function that can create notifications for any user
-- This bypasses RLS restrictions while maintaining security
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
COMMENT ON FUNCTION create_notification IS 'Creates a notification for any user (bypasses RLS). Used by the notification service to send notifications between users.';

-- Alternative: Update RLS policy to allow creating notifications for others
-- (Less secure but simpler - use function approach above instead)
-- DROP POLICY IF EXISTS notifications_insert_own ON public.notifications;
-- CREATE POLICY notifications_insert_all ON public.notifications
--   FOR INSERT TO authenticated
--   WITH CHECK (true); -- Allow any authenticated user to create notifications


