# Booking Cancellation System - Migration Instructions

## Step-by-Step Setup

### Step 1: Run the Main Migration
Run `create_booking_cancellation_system.sql` in your Supabase SQL Editor. This will:
- ✅ Add cancellation fields to the `bookings` table
- ✅ Create the `booking_cancellations` table
- ✅ Add all constraints and indexes
- ✅ Set up RLS policies
- ✅ Create SQL functions

**This is the main file you should run first!**

### Step 2: If You Get Constraint Errors
If you encounter the error: `constraint "booking_cancellations_user_type_check" already exists`, it means the table was partially created. In this case:

1. First, check if the table exists:
   ```sql
   SELECT EXISTS (
     SELECT FROM information_schema.tables 
     WHERE table_schema = 'public' 
     AND table_name = 'booking_cancellations'
   );
   ```

2. If the table exists, run `fix_booking_cancellation_constraint.sql` to fix the constraint issue.

3. Then continue with the rest of `create_booking_cancellation_system.sql` (skip the table creation part).

### Step 3: Verify Installation
After running the migration, verify everything was created:

```sql
-- Check if table exists
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name = 'booking_cancellations';

-- Check if columns were added to bookings table
SELECT column_name 
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'bookings' 
AND column_name IN ('cancelled_at', 'cancelled_by', 'cancellation_reason', 'cancellation_notes');

-- Check if functions exist
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name LIKE '%cancellation%';
```

## Troubleshooting

### Error: "relation booking_cancellations does not exist"
**Solution:** Run `create_booking_cancellation_system.sql` first to create the table.

### Error: "constraint already exists"
**Solution:** The updated `create_booking_cancellation_system.sql` now handles this automatically with `DROP CONSTRAINT IF EXISTS`. If you still get this error, run `fix_booking_cancellation_constraint.sql`.

### Error: "column already exists"
**Solution:** The migration uses `ADD COLUMN IF NOT EXISTS`, so this should not happen. If it does, the columns already exist and you can continue.

## Order of Execution

1. ✅ Run `create_booking_cancellation_system.sql` (main migration)
2. ✅ If errors occur, fix them with the specific fix file
3. ✅ Verify installation with the verification queries above
4. ✅ Test the cancellation functionality in the app


