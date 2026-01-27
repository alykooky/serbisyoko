-- ============================================================
-- FIX WORKER_AVAILABILITY TABLE
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Option 1: Add updated_at column to the table (if you want timestamps)
ALTER TABLE public.worker_availability
ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Create a trigger to automatically update updated_at on UPDATE
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS update_worker_availability_updated_at ON public.worker_availability;

-- Create trigger only if updated_at column exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'worker_availability' 
        AND column_name = 'updated_at'
    ) THEN
        CREATE TRIGGER update_worker_availability_updated_at
        BEFORE UPDATE ON public.worker_availability
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- ALTERNATIVE: If you don't want updated_at, remove the trigger
-- ============================================================
-- DROP TRIGGER IF EXISTS update_worker_availability_updated_at ON public.worker_availability;

-- ============================================================
-- Verify the table structure
-- ============================================================
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_schema = 'public' 
-- AND table_name = 'worker_availability'
-- ORDER BY ordinal_position;


