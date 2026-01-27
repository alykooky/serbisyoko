# SerbisyoKo In-App Chat System

## Overview
The SerbisyoKo app features a comprehensive real-time messaging system that allows clients and service providers to communicate seamlessly before, during, and after service delivery.

## Features

### 🚀 Real-time Messaging
- **Instant delivery**: Messages are sent and received in real-time using Supabase Realtime
- **Read receipts**: Visual indicators show when messages have been read
- **Typing indicators**: (Future enhancement)
- **Message status**: Sent, delivered, and read status tracking

### 💬 Chat Interface
- **Modern UI**: Clean, intuitive chat interface with message bubbles
- **Responsive design**: Works seamlessly on all screen sizes
- **Message history**: Persistent message storage and retrieval
- **Auto-scroll**: Automatically scrolls to latest messages

### 🔐 Security & Privacy
- **Row Level Security (RLS)**: Messages are only visible to participants
- **User authentication**: Only authenticated users can send/receive messages
- **Data encryption**: All messages are encrypted in transit and at rest

### 📱 User Experience
- **Conversation list**: Easy access to all active conversations
- **Search functionality**: (Future enhancement)
- **Message threading**: (Future enhancement)
- **File sharing**: (Future enhancement)

## Database Schema

### Messages Table
```sql
CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
  content text NOT NULL,
  message_type text CHECK (message_type IN ('text', 'image', 'file', 'location')) DEFAULT 'text',
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
```

### RLS Policies
- **messages_select_participants**: Users can only see messages they sent or received
- **messages_insert_sender**: Users can only send messages as themselves
- **messages_update_read_status**: Users can only mark messages as read if they're the receiver

## File Structure

```
lib/
├── chat_screen.dart              # Main chat interface
├── chat_list_screen.dart         # Conversation list
├── services/
│   └── chat_service.dart         # Chat business logic
└── widgets/
    └── chat_bubble.dart          # Reusable message bubble widget
```

## Usage

### Starting a Chat
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ChatScreen(
      receiverId: 'user-uuid',
      receiverName: 'John Doe',
      receiverAvatar: 'https://example.com/avatar.jpg',
      bookingId: 'booking-uuid', // Optional
    ),
  ),
);
```

### Sending a Message
```dart
final success = await ChatService.sendMessage(
  receiverId: 'user-uuid',
  content: 'Hello! How are you?',
  bookingId: 'booking-uuid', // Optional
);
```

### Getting Conversations
```dart
final conversations = await ChatService.getConversations();
```

### Real-time Subscription
```dart
final channel = ChatService.subscribeToMessages(
  otherUserId: 'user-uuid',
  onNewMessage: (message) {
    // Handle new message
    print('New message: ${message['content']}');
  },
);

// Don't forget to unsubscribe
ChatService.unsubscribeFromMessages('user-uuid');
```

## Integration Points

### 1. Provider Profile
- "Message" button opens chat with the service provider
- Direct integration with booking context

### 2. Dashboard Navigation
- Chat icon in bottom navigation bar
- Access to all conversations

### 3. Booking System
- Chat can be associated with specific bookings
- Context-aware messaging

## Future Enhancements

### Phase 2 Features
- [ ] **File sharing**: Images, documents, and other files
- [ ] **Voice messages**: Audio recording and playback
- [ ] **Location sharing**: Send current location
- [ ] **Message search**: Find specific messages
- [ ] **Message reactions**: Emoji reactions to messages
- [ ] **Message threading**: Reply to specific messages
- [ ] **Group chats**: Multiple participants
- [ ] **Push notifications**: Real-time notifications
- [ ] **Message encryption**: End-to-end encryption
- [ ] **Typing indicators**: Show when someone is typing

### Phase 3 Features
- [ ] **Video calls**: Integrated video calling
- [ ] **Screen sharing**: Share screen during calls
- [ ] **Message translation**: Auto-translate messages
- [ ] **AI assistant**: Chatbot integration
- [ ] **Message scheduling**: Send messages at specific times
- [ ] **Message templates**: Pre-written message templates

## Technical Details

### Dependencies
- `supabase_flutter`: Real-time database and authentication
- `flutter/material`: UI components
- `dart:async`: Asynchronous programming

### Performance Considerations
- **Message pagination**: Load messages in batches to improve performance
- **Connection management**: Properly subscribe/unsubscribe from channels
- **Memory management**: Dispose of controllers and streams
- **Error handling**: Graceful handling of network errors

### Security Considerations
- **Input validation**: Sanitize user input
- **Rate limiting**: Prevent spam messages
- **Content moderation**: (Future enhancement)
- **Data retention**: Automatic message cleanup policies

## Testing

### Unit Tests
- Chat service methods
- Message validation
- Database operations

### Integration Tests
- Real-time messaging flow
- User authentication
- RLS policy enforcement

### UI Tests
- Chat interface interactions
- Message sending/receiving
- Navigation flows

## Troubleshooting

### Common Issues
1. **Messages not appearing**: Check RLS policies and user authentication
2. **Real-time not working**: Verify Supabase Realtime is enabled
3. **Performance issues**: Implement message pagination
4. **Memory leaks**: Ensure proper disposal of streams and controllers

### Debug Mode
Enable debug logging in `ChatService` to troubleshoot issues:
```dart
// Add debug prints in ChatService methods
print('Debug: Sending message to $receiverId');
```

## Support

For technical support or feature requests, please contact the development team or create an issue in the project repository.

---

**Version**: 1.0.0  
**Last Updated**: December 2024  
**Maintainer**: SerbisyoKo Development Team

