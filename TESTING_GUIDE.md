# Testing Guide for Matching Algorithm

## What Was Fixed

1. ✅ **Performance Calculation**: Now uses `(Jobs Done / Highest Jobs Done) × (Rating / 5)`
2. ✅ **Location Score**: Uses `Nearest Distance / Worker Distance` formula
3. ✅ **Console Logging**: Detailed score breakdowns for each worker
4. ✅ **Form Data**: Client request form now passes budget, date, and time
5. ✅ **Service Integration**: Smart matching results now uses `AdvancedMatchingService`

## How to Test

### Step 1: Run the Application

```bash
flutter run
```

Or use your IDE's run button.

### Step 2: Navigate to Client Request Form

1. Log in as a client
2. Navigate to the service request form (usually through categories or dashboard)
3. Select a service type (e.g., "Plumbing", "Electrician", etc.)

### Step 3: Fill Out the Form

The form should now have:
- ✅ **Description field** (What do you need?)
- ✅ **Budget Range** (Min and Max)
- ✅ **Date Picker** (Select Date button)
- ✅ **Time Picker** (Select Time button)
- ✅ **Find Available Workers** button

**Important**: Make sure to:
- Select both date AND time (form will show error if missing)
- Enter a budget range (e.g., Min: 100, Max: 500)

### Step 4: Check Console Output

When you click "Find Available Workers", watch your console/terminal. You should see:

```
▶️ MATCHING STARTED
Service: [service name]
Location: [latitude], [longitude]
Budget: [min] - [max]
────

🟢 Worker Loaded: [worker name], skills=[skill list]

📊 [Worker Name] Score Breakdown:
  ┌─ Skills:       1.000 × 0.25 = 0.250
  ├─ Performance:  0.671 × 0.20 = 0.134
  │  └─ (Jobs Done: 25/35, Rating: 4.7/5.0)
  ├─ Availability: 1.000 × 0.15 = 0.150
  ├─ Credentials:  1.000 × 0.15 = 0.150
  ├─ Location:     1.000 × 0.15 = 0.150
  │  └─ Distance: 1.00 km (Nearest: 1.00 km)
  ├─ Fee:          1.000 × 0.10 = 0.100
  │  └─ Hourly Rate: ₱500 (Budget: ₱100-₱500)
  └─ TOTAL SCORE:  0.9340

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Results for '[service name]'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 5: Verify Results Screen

After matching completes, you should see:

1. **List of matched workers** (sorted by score, highest first)
2. **Each worker card showing**:
   - Worker name
   - Total match score
   - Distance in km
   - Hourly rate
   - Skills chips
   - **Score Breakdown**:
     - Skills Match
     - Performance
     - Availability
     - Credentials
     - Location Score
     - Fee Score

### Step 6: Verify Matching Logic

Check that:
- ✅ Workers with matching skills appear
- ✅ Workers are sorted by total score (highest first)
- ✅ Console shows detailed breakdown for each worker
- ✅ Location scores are calculated correctly (closer = higher score)
- ✅ Performance scores combine jobs done and ratings correctly

## Expected Console Output Format

For each worker, you should see:

```
📊 [Worker Name] Score Breakdown:
  ┌─ Skills:       [score] × 0.25 = [weighted]
  ├─ Performance:  [score] × 0.20 = [weighted]
  │  └─ (Jobs Done: X/Y, Rating: Z/5.0)
  ├─ Availability: [score] × 0.15 = [weighted]
  ├─ Credentials:  [score] × 0.15 = [weighted]
  ├─ Location:     [score] × 0.15 = [weighted]
  │  └─ Distance: X.XX km (Nearest: Y.YY km)
  ├─ Fee:          [score] × 0.10 = [weighted]
  │  └─ Hourly Rate: ₱XXX (Budget: ₱XXX-₱XXX)
  └─ TOTAL SCORE:  [total]
```

## Troubleshooting

### No workers matched?
- Check console for error messages
- Verify workers exist in database with:
  - Matching skills
  - Availability status != 'OFF'
  - Valid coordinates (lat/lng)
- Check if location is too restrictive (search radius is 15km)

### Missing console output?
- Ensure you're running in debug mode
- Check that `debugPrint` statements are visible in your console
- Look for any errors before the matching starts

### Form not submitting?
- Verify both date AND time are selected
- Check that budget values are valid numbers
- Look for error messages in the UI

### Score calculation looks wrong?
- Verify Performance = (Jobs/Highest) × (Rating/5)
- Verify Location = Nearest Distance / Worker Distance
- Check that weights sum correctly: 0.25 + 0.20 + 0.15 + 0.15 + 0.15 + 0.10 = 1.00

## Test Cases to Try

1. **Basic Match**: Service with known workers in database
2. **Budget Range**: Workers with rates within and outside budget
3. **Distance**: Workers at different distances from client
4. **Performance**: Workers with different job counts and ratings
5. **No Match**: Service type with no workers (should show "No workers matched")

## Success Criteria

✅ Console shows detailed score breakdowns
✅ Workers are matched and displayed
✅ Scores are calculated correctly
✅ Workers sorted by total score
✅ All factors (Skills, Performance, Availability, Credentials, Location, Fee) are visible in breakdown


