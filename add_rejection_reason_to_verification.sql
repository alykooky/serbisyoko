-- ============================================================
-- ADD REJECTION REASON TO VERIFICATION REQUESTS
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Add rejection_reason column to verification_requests table
ALTER TABLE public.verification_requests 
ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Add comment
COMMENT ON COLUMN public.verification_requests.rejection_reason IS 'Reason provided by admin when rejecting a verification request';

