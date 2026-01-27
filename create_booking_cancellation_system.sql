-- ============================================================
-- BOOKING CANCELLATION SYSTEM
-- Run this in your Supabase SQL Editor
-- ============================================================

-- 1. Add cancellation fields to bookings table
ALTER TABLE public.bookings
ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
ADD COLUMN IF NOT EXISTS cancelled_by text, -- 'client', 'worker', or 'system'
ADD COLUMN IF NOT EXISTS cancellation_reason text,
ADD COLUMN IF NOT EXISTS cancellation_notes text;

-- 2. Create booking_cancellations table for tracking (abuse prevention)
CREATE TABLE IF NOT EXISTS public.booking_cancellations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_type text NOT NULL,
    booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
    reason text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Add check constraint for user_type (drop and recreate to avoid conflicts)
ALTER TABLE public.booking_cancellations
DROP CONSTRAINT IF EXISTS booking_cancellations_user_type_check;

ALTER TABLE public.booking_cancellations
ADD CONSTRAINT booking_cancellations_user_type_check 
CHECK (user_type IN ('client', 'worker'));

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_booking_cancellations_user_id ON public.booking_cancellations(user_id);
CREATE INDEX IF NOT EXISTS idx_booking_cancellations_user_type ON public.booking_cancellations(user_type);
CREATE INDEX IF NOT EXISTS idx_booking_cancellations_created_at ON public.booking_cancellations(created_at);
CREATE INDEX IF NOT EXISTS idx_booking_cancellations_booking_id ON public.booking_cancellations(booking_id);

-- 3. Update bookings table to support new cancellation statuses
-- Note: You might want to add a CHECK constraint, but for flexibility, we'll just document valid statuses:
-- Valid statuses: 'pending', 'accepted', 'inprogress', 'completed', 
--                 'cancelled_by_client', 'cancelled_by_worker', 
--                 'auto_cancelled_no_response', 'auto_cancelled_unconfirmed', 'declined'

-- 4. RLS Policies for booking_cancellations
ALTER TABLE public.booking_cancellations ENABLE ROW LEVEL SECURITY;

-- Users can view their own cancellation records
DROP POLICY IF EXISTS "Users can view their own cancellation records" ON public.booking_cancellations;
CREATE POLICY "Users can view their own cancellation records"
    ON public.booking_cancellations
    FOR SELECT
    USING (auth.uid() = user_id);

-- System can insert cancellation records (handled by service)
DROP POLICY IF EXISTS "Service can insert cancellation records" ON public.booking_cancellations;
CREATE POLICY "Service can insert cancellation records"
    ON public.booking_cancellations
    FOR INSERT
    WITH CHECK (true); -- Service role will handle this

-- 5. Function to get cancellation count for a user
CREATE OR REPLACE FUNCTION get_user_cancellation_count(
    p_user_id uuid,
    p_days integer DEFAULT 30
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count integer;
    v_cutoff_date timestamptz;
BEGIN
    v_cutoff_date := now() - (p_days || ' days')::interval;
    
    SELECT COUNT(*) INTO v_count
    FROM public.booking_cancellations
    WHERE user_id = p_user_id
      AND created_at >= v_cutoff_date;
    
    RETURN COALESCE(v_count, 0);
END;
$$;

-- 6. Function to check if user has exceeded cancellation limit
CREATE OR REPLACE FUNCTION has_exceeded_cancellation_limit(
    p_user_id uuid,
    p_max_cancellations integer DEFAULT 5,
    p_days integer DEFAULT 30
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count integer;
BEGIN
    v_count := get_user_cancellation_count(p_user_id, p_days);
    RETURN v_count >= p_max_cancellations;
END;
$$;

-- 7. Function to auto-cancel unresponded bookings (call via pg_cron or scheduled job)
CREATE OR REPLACE FUNCTION auto_cancel_unresponded_bookings(
    p_minutes_threshold integer DEFAULT 30
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count integer;
    v_cutoff_time timestamptz;
    v_booking_record RECORD;
BEGIN
    v_cutoff_time := now() - (p_minutes_threshold || ' minutes')::interval;
    v_count := 0;
    
    -- Find and cancel pending bookings older than threshold
    FOR v_booking_record IN
        SELECT id, client_id, service_type, worker_id
        FROM public.bookings
        WHERE status = 'pending'
          AND created_at < v_cutoff_time
    LOOP
        -- Update booking status
        UPDATE public.bookings
        SET 
            status = 'auto_cancelled_no_response',
            cancelled_at = now(),
            cancelled_by = 'system',
            cancellation_reason = format('Worker did not respond within %s minutes', p_minutes_threshold)
        WHERE id = v_booking_record.id;
        
        -- Track cancellation (for client)
        INSERT INTO public.booking_cancellations (user_id, user_type, booking_id, reason)
        VALUES (
            v_booking_record.client_id,
            'client',
            v_booking_record.id,
            format('Auto-cancelled: Worker did not respond within %s minutes', p_minutes_threshold)
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;

-- 8. Function to auto-cancel unconfirmed bookings (call via pg_cron or scheduled job)
CREATE OR REPLACE FUNCTION auto_cancel_unconfirmed_bookings(
    p_hours_threshold integer DEFAULT 24
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count integer;
    v_cutoff_time timestamptz;
    v_booking_record RECORD;
BEGIN
    v_cutoff_time := now() - (p_hours_threshold || ' hours')::interval;
    v_count := 0;
    
    -- Find and cancel accepted bookings where client hasn't confirmed (older than threshold)
    FOR v_booking_record IN
        SELECT id, client_id, service_type, worker_id
        FROM public.bookings
        WHERE status = 'accepted'
          AND updated_at < v_cutoff_time
    LOOP
        -- Update booking status
        UPDATE public.bookings
        SET 
            status = 'auto_cancelled_unconfirmed',
            cancelled_at = now(),
            cancelled_by = 'system',
            cancellation_reason = format('Client did not confirm within %s hours', p_hours_threshold)
        WHERE id = v_booking_record.id;
        
        -- Track cancellation (for both client and worker)
        INSERT INTO public.booking_cancellations (user_id, user_type, booking_id, reason)
        VALUES 
        (
            v_booking_record.client_id,
            'client',
            v_booking_record.id,
            format('Auto-cancelled: Not confirmed within %s hours', p_hours_threshold)
        ),
        (
            v_booking_record.worker_id,
            'worker',
            v_booking_record.id,
            format('Auto-cancelled: Client did not confirm within %s hours', p_hours_threshold)
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;

-- ============================================================
-- SET UP AUTOMATED JOBS (pg_cron)
-- ============================================================
-- Note: These commands require pg_cron extension enabled in Supabase
-- You can also call these functions manually or via a scheduled API endpoint

-- Example: Schedule auto-cancel unresponded bookings every 15 minutes
-- SELECT cron.schedule(
--     'auto-cancel-unresponded',
--     '*/15 * * * *', -- Every 15 minutes
--     $$SELECT auto_cancel_unresponded_bookings(30);$$
-- );

-- Example: Schedule auto-cancel unconfirmed bookings every hour
-- SELECT cron.schedule(
--     'auto-cancel-unconfirmed',
--     '0 * * * *', -- Every hour
--     $$SELECT auto_cancel_unconfirmed_bookings(24);$$
-- );

-- ============================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================
COMMENT ON COLUMN public.bookings.cancelled_at IS 'Timestamp when booking was cancelled';
COMMENT ON COLUMN public.bookings.cancelled_by IS 'Who cancelled: client, worker, or system';
COMMENT ON COLUMN public.bookings.cancellation_reason IS 'Reason code/description for cancellation';
COMMENT ON COLUMN public.bookings.cancellation_notes IS 'Additional notes about cancellation';

COMMENT ON TABLE public.booking_cancellations IS 'Tracks all booking cancellations for abuse prevention and analytics';
COMMENT ON FUNCTION get_user_cancellation_count IS 'Get count of cancellations by a user within specified days';
COMMENT ON FUNCTION has_exceeded_cancellation_limit IS 'Check if user has exceeded monthly cancellation limit';
COMMENT ON FUNCTION auto_cancel_unresponded_bookings IS 'Auto-cancel bookings where worker did not respond in time';
COMMENT ON FUNCTION auto_cancel_unconfirmed_bookings IS 'Auto-cancel bookings where client did not confirm in time';

