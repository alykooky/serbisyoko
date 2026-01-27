-- ============================================================
-- ADMIN AUDIT LOGS TABLE
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Create audit_logs table for tracking admin actions
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  admin_email text,
  action_type text NOT NULL, -- 'verification_approved', 'verification_rejected', 'user_blocked', etc.
  entity_type text NOT NULL, -- 'verification_request', 'user', 'booking', etc.
  entity_id uuid,
  details jsonb, -- Additional details like reason, old_value, new_value
  ip_address text,
  user_agent text,
  created_at timestamptz DEFAULT now()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS admin_audit_logs_admin_id_idx ON public.admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS admin_audit_logs_action_type_idx ON public.admin_audit_logs(action_type);
CREATE INDEX IF NOT EXISTS admin_audit_logs_entity_type_idx ON public.admin_audit_logs(entity_type);
CREATE INDEX IF NOT EXISTS admin_audit_logs_created_at_idx ON public.admin_audit_logs(created_at DESC);

-- Enable RLS
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Only admins can view audit logs
CREATE POLICY admin_audit_logs_select_admin 
ON public.admin_audit_logs
FOR SELECT 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() 
    AND role = 'Admin'
  )
);

-- Allow admins to insert audit logs
CREATE POLICY admin_audit_logs_insert_admin 
ON public.admin_audit_logs
FOR INSERT 
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() 
    AND role = 'Admin'
  )
);

-- Add comment
COMMENT ON TABLE public.admin_audit_logs IS 'Audit log for tracking all admin actions and changes';

