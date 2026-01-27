# Where to View Audit Logs

## 📍 Access Points

### 1. **Admin Dashboard** (Main Access)
- Go to **Admin Dashboard**
- Scroll down to the **"Admin Actions"** section
- Click on the **"Audit Logs"** card
- This is the primary way to view audit logs

### 2. **Direct Navigation**
- You can navigate directly to the Audit Logs screen from anywhere in the admin section
- The screen path is: `AdminAuditLogsScreen`

## 🎯 Features

The Audit Logs screen includes:

### ✅ **Filtering Options**
- **Filter by Action Type:**
  - All Actions
  - Verification Approved
  - Verification Rejected
  - User Blocked
  - User Unblocked

- **Filter by Entity Type:**
  - All Entities
  - Verification Request
  - User
  - Booking

### ✅ **Detailed View**
Each audit log entry shows:
- **Action Type** (with colored icon)
- **Admin Email** (who performed the action)
- **Timestamp** (when the action occurred)
- **Entity Type & ID**
- **Details** (including rejection reasons, user info, etc.)
- **IP Address** (if available)

### ✅ **Expandable Cards**
- Tap on any log entry to see full details
- Color-coded icons:
  - 🟢 Green = Approved actions
  - 🔴 Red = Rejected/Blocked actions
  - 🔵 Blue = Other actions

### ✅ **Refresh**
- Pull down to refresh the logs
- Or click the refresh button in the AppBar

## 📊 What Gets Logged

Currently, the system logs:
- ✅ Verification approvals
- ✅ Verification rejections (with reason)
- Future actions can be added to the logging system

## 🔍 Example Log Entry

```
Action: Verification Rejected
By: admin@example.com
Date: Dec 15, 2024 • 2:30 PM

Entity Type: verification_request
Entity ID: abc-123-def

Details:
- USER_ID: worker-123
- FULL_NAME: John Doe
- REJECTION_REASON: Missing NBI clearance document
```

## 💡 Tips

1. **Use Filters**: Narrow down logs by action or entity type
2. **Expand Details**: Click any log entry to see full information
3. **Refresh Regularly**: Pull down to get the latest logs
4. **Check Timestamps**: All actions include exact date and time

## 🛠️ Technical Details

- **Table**: `admin_audit_logs`
- **Service**: `AdminAuditService`
- **Screen**: `AdminAuditLogsScreen`
- **Access**: Admin role required (RLS enforced)

---

**Note**: Make sure you've run the `create_admin_audit_logs.sql` migration file in Supabase to create the audit logs table!

