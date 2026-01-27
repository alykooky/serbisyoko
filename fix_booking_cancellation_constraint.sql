-- ============================================================
-- FIX BOOKING CANCELLATION CONSTRAINT ERROR
-- Run this ONLY if you get "constraint already exists" error
-- AND the table booking_cancellations already exists
-- ============================================================

-- Check if table exists first
DO $$
BEGIN
    -- Only proceed if table exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'booking_cancellations'
    ) THEN
        -- Drop the constraint if it exists, then recreate it
        ALTER TABLE public.booking_cancellations
        DROP CONSTRAINT IF EXISTS booking_cancellations_user_type_check;

        -- Re-add the constraint
        ALTER TABLE public.booking_cancellations
        ADD CONSTRAINT booking_cancellations_user_type_check 
        CHECK (user_type IN ('client', 'worker'));
        
        RAISE NOTICE 'Constraint fixed successfully';
    ELSE
        RAISE NOTICE 'Table booking_cancellations does not exist yet. Please run create_booking_cancellation_system.sql first.';
    END IF;
END $$;

