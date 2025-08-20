import { db, transaction } from './db';

// Conversation related types
export interface Conversation {
  id: string;
  title?: string;
  type: 'direct' | 'group';
  created_at: number;
  updated_at: number;
}

export interface ConversationMember {
  id: string;
  conversation_id: string;
  user_id: string;
  is_admin: boolean;
  joined_at: number;
  last_read_at: number;
}

export interface Message {
  id: string;
  conversation_id: string;
  sender_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  content_type: string;
  created_at: number;
  interpretation_json?: string;
  processed: number;
  stored_record_id?: string;
}

// Function to get user's conversations with latest message and unread count
export function getConversations(userId: string) {
  return db.prepare(`
    WITH latest_messages AS (
      SELECT 
        m.*,
        ROW_NUMBER() OVER (PARTITION BY m.conversation_id ORDER BY m.created_at DESC) as rn
      FROM messages m
      JOIN conversation_members cm ON m.conversation_id = cm.conversation_id
      WHERE cm.user_id = ?
    ),
    unread_counts AS (
      SELECT 
        m.conversation_id,
        COUNT(*) as count
      FROM messages m
      JOIN conversation_members cm ON m.conversation_id = cm.conversation_id
      WHERE cm.user_id = ?
        AND m.created_at > cm.last_read_at
        AND m.sender_id != ?
      GROUP BY m.conversation_id
    )
    SELECT 
      c.*,
      GROUP_CONCAT(u.name) as member_names,
      lm.content as last_message,
      lm.created_at as last_message_at,
      COALESCE(uc.count, 0) as unread_count
    FROM conversations c
    JOIN conversation_members cm ON c.id = cm.conversation_id
    JOIN users u ON cm.user_id = u.id
    LEFT JOIN latest_messages lm ON c.id = lm.conversation_id AND lm.rn = 1
    LEFT JOIN unread_counts uc ON c.id = uc.conversation_id
    WHERE c.id IN (
      SELECT conversation_id 
      FROM conversation_members 
      WHERE user_id = ?
    )
    GROUP BY c.id
    ORDER BY COALESCE(lm.created_at, c.created_at) DESC
  `).all([userId, userId, userId, userId]);
}

// Function to get messages for a conversation
export function getMessages(conversationId: string, userId: string, limit = 50, before?: number) {
  const params: any[] = [conversationId];
  let sql = `
    SELECT 
      m.*,
      u.name as sender_name,
      u.id = ? as is_me
    FROM messages m
    JOIN users u ON m.sender_id = u.id
    WHERE m.conversation_id = ?
  `;
  
  if (before) {
    sql += ' AND m.created_at < ?';
    params.push(before);
  }
  
  sql += ' ORDER BY m.created_at DESC LIMIT ?';
  params.unshift(userId);
  params.push(limit);
  
  return db.prepare(sql).all(params);
}

// Function to send a message
export function sendMessage(message: Omit<Message, 'id' | 'created_at'>) {
  const now = Date.now();
  const messageId = `msg_${now}`;
  
  db.prepare(`
    INSERT INTO messages (
      id, conversation_id, sender_id, role, content, 
      content_type, created_at, interpretation_json,
      processed, stored_record_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run([
    messageId,
    message.conversation_id,
    message.sender_id,
    message.role,
    message.content,
    message.content_type,
    now,
    message.interpretation_json,
    message.processed,
    message.stored_record_id
  ]);
  
  // Update conversation's updated_at timestamp
  db.prepare(`
    UPDATE conversations 
    SET updated_at = ? 
    WHERE id = ?
  `).run([now, message.conversation_id]);
  
  return messageId;
}

// Function to create a new conversation
export function createConversation(
  title: string | null,
  type: 'direct' | 'group',
  memberIds: string[],
  creatorId: string
) {
  const now = Date.now();
  const conversationId = `conv_${now}`;
  
  return transaction(() => {
    // Create conversation
    db.prepare(`
      INSERT INTO conversations (id, title, type, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).run([conversationId, title, type, now, now]);
    
    // Add members
    const addMember = db.prepare(`
      INSERT INTO conversation_members (
        id, conversation_id, user_id, is_admin, joined_at, last_read_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    `);
    
    for (const userId of memberIds) {
      const memberId = `member_${now}_${userId}`;
      addMember.run([
        memberId,
        conversationId,
        userId,
        userId === creatorId ? 1 : 0, // Creator is admin
        now,
        now
      ]);
    }
    
    return conversationId;
  });
}

// Function to mark messages as read
export function markConversationAsRead(conversationId: string, userId: string) {
  return db.prepare(`
    UPDATE conversation_members
    SET last_read_at = ?
    WHERE conversation_id = ? AND user_id = ?
  `).run([Date.now(), conversationId, userId]);
}

// Function to update conversation title (for group chats)
export function updateConversationTitle(conversationId: string, title: string) {
  return db.prepare(`
    UPDATE conversations
    SET title = ?
    WHERE id = ?
  `).run([title, conversationId]);
}

// Function to add members to a conversation
export function addConversationMembers(conversationId: string, userIds: string[]) {
  const now = Date.now();
  
  return transaction(() => {
    const addMember = db.prepare(`
      INSERT INTO conversation_members (
        id, conversation_id, user_id, is_admin, joined_at, last_read_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    `);
    
    for (const userId of userIds) {
      const memberId = `member_${now}_${userId}`;
      addMember.run([
        memberId,
        conversationId,
        userId,
        0, // Not admin
        now,
        now
      ]);
    }
  });
}

// Function to remove a member from a conversation
export function removeConversationMember(conversationId: string, userId: string) {
  return db.prepare(`
    DELETE FROM conversation_members
    WHERE conversation_id = ? AND user_id = ?
  `).run([conversationId, userId]);
}

// Function to get conversation members
export function getConversationMembers(conversationId: string) {
  return db.prepare(`
    SELECT 
      cm.*,
      u.name,
      u.email,
      u.photo_url
    FROM conversation_members cm
    JOIN users u ON cm.user_id = u.id
    WHERE cm.conversation_id = ?
    ORDER BY cm.is_admin DESC, cm.joined_at ASC
  `).all([conversationId]);
}
