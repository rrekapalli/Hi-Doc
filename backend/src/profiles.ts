import { db, transaction } from './db.js';

// Profile related types (renamed from Conversation)
export interface Profile {
  id: string;
  title?: string;
  type: 'direct' | 'group';
  created_at: number;
  updated_at: number;
}

export interface ProfileMember {
  id: string;
  profile_id: string;
  user_id: string;
  is_admin: boolean;
  joined_at: number;
  last_read_at: number;
}

export interface Message {
  id: string;
  profile_id: string;
  sender_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  content_type: string;
  created_at: number;
  interpretation_json?: string;
  processed: number;
  stored_record_id?: string;
}

// Function to get user's profiles with latest message and unread count
export function getProfiles(userId: string) {
  return db.prepare(`
    WITH latest_messages AS (
      SELECT 
        m.*, 
        ROW_NUMBER() OVER (PARTITION BY m.profile_id ORDER BY m.created_at DESC) as rn
      FROM messages m
      JOIN profile_members pm ON m.profile_id = pm.profile_id
      WHERE pm.user_id = ?
    ),
    unread_counts AS (
      SELECT 
        m.profile_id,
        COUNT(*) as count
      FROM messages m
      JOIN profile_members pm ON m.profile_id = pm.profile_id
      WHERE pm.user_id = ?
        AND m.created_at > pm.last_read_at
        AND m.sender_id != ?
      GROUP BY m.profile_id
    )
    SELECT 
      p.*,
      GROUP_CONCAT(u.name) as member_names,
      lm.content as last_message,
      lm.created_at as last_message_at,
      COALESCE(uc.count, 0) as unread_count
    FROM profiles p
    JOIN profile_members pm ON p.id = pm.profile_id
    JOIN users u ON pm.user_id = u.id
    LEFT JOIN latest_messages lm ON p.id = lm.profile_id AND lm.rn = 1
    LEFT JOIN unread_counts uc ON p.id = uc.profile_id
    WHERE p.id IN (
      SELECT profile_id 
      FROM profile_members 
      WHERE user_id = ?
    )
    GROUP BY p.id
    ORDER BY COALESCE(lm.created_at, p.created_at) DESC
  `).all([userId, userId, userId, userId]);
}

// Function to get messages for a profile
export function getMessages(profileId: string, userId: string, limit = 50, before?: number) {
  const params: any[] = [profileId];
  let sql = `
    SELECT 
      m.*,
      u.name as sender_name,
      u.id = ? as is_me
    FROM messages m
    JOIN users u ON m.sender_id = u.id
    WHERE m.profile_id = ?
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
  // Legacy compatibility: some DBs may still have NOT NULL profile_id
  // Detect columns once
  const cols = db.prepare('PRAGMA table_info(messages)').all() as any[];
  const hasConversationId = cols.some(c => c.name === 'profile_id');
  const hasProfileId = cols.some(c => c.name === 'profile_id');

  if (hasConversationId && !hasProfileId) {
    db.prepare(`
      INSERT INTO messages (
        id, profile_id, sender_id, role, content,
        content_type, created_at, interpretation_json,
        processed, stored_record_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run([
      messageId,
      message.profile_id,
      message.sender_id,
      message.role,
      message.content,
      message.content_type,
      now,
      message.interpretation_json,
      message.processed,
      message.stored_record_id
    ]);
  } else if (hasConversationId && hasProfileId) {
    db.prepare(`
      INSERT INTO messages (
        id, profile_id, profile_id, sender_id, role, content,
        content_type, created_at, interpretation_json,
        processed, stored_record_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run([
      messageId,
      message.profile_id,
      message.profile_id,
      message.sender_id,
      message.role,
      message.content,
      message.content_type,
      now,
      message.interpretation_json,
      message.processed,
      message.stored_record_id
    ]);
  } else {
    db.prepare(`
      INSERT INTO messages (
        id, profile_id, sender_id, role, content,
        content_type, created_at, interpretation_json,
        processed, stored_record_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run([
      messageId,
      message.profile_id,
      message.sender_id,
      message.role,
      message.content,
      message.content_type,
      now,
      message.interpretation_json,
      message.processed,
      message.stored_record_id
    ]);
  }
  
  // Update profile's updated_at timestamp
  db.prepare(`
    UPDATE profiles 
    SET updated_at = ? 
    WHERE id = ?
  `).run([now, message.profile_id]);
  
  return messageId;
}

// Function to create a new profile
export function createProfile(
  title: string | null,
  type: 'direct' | 'group',
  memberIds: string[],
  creatorId: string
) {
  const now = Date.now();
  const profileId = `prof_${now}`;
  
  return transaction(() => {
    // Create profile
    db.prepare(`
      INSERT INTO profiles (id, title, type, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).run([profileId, title, type, now, now]);
    
    // Add members
    const addMember = db.prepare(`
      INSERT INTO profile_members (
        id, profile_id, user_id, is_admin, joined_at, last_read_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    `);
    
    for (const userId of memberIds) {
      const memberId = `member_${now}_${userId}`;
      addMember.run([
        memberId,
        profileId,
        userId,
        userId === creatorId ? 1 : 0, // Creator is admin
        now,
        now
      ]);
    }
    
    return profileId;
  });
}

// Function to mark messages as read
export function markProfileAsRead(profileId: string, userId: string) {
  return db.prepare(`
    UPDATE profile_members
    SET last_read_at = ?
    WHERE profile_id = ? AND user_id = ?
  `).run([Date.now(), profileId, userId]);
}

// Function to update profile title (for group chats)
export function updateProfileTitle(profileId: string, title: string) {
  return db.prepare(`
    UPDATE profiles
    SET title = ?
    WHERE id = ?
  `).run([title, profileId]);
}

// Function to add members to a profile
export function addProfileMembers(profileId: string, userIds: string[]) {
  const now = Date.now();
  
  return transaction(() => {
    const addMember = db.prepare(`
      INSERT INTO profile_members (
        id, profile_id, user_id, is_admin, joined_at, last_read_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    `);
    
    for (const userId of userIds) {
      const memberId = `member_${now}_${userId}`;
      addMember.run([
        memberId,
        profileId,
        userId,
        0, // Not admin
        now,
        now
      ]);
    }
  });
}

// Function to remove a member from a profile
export function removeProfileMember(profileId: string, userId: string) {
  return db.prepare(`
    DELETE FROM profile_members
    WHERE profile_id = ? AND user_id = ?
  `).run([profileId, userId]);
}

// Function to get profile members
export function getProfileMembers(profileId: string) {
  return db.prepare(`
    SELECT 
      pm.*,
      u.name,
      u.email,
      u.photo_url
    FROM profile_members pm
    JOIN users u ON pm.user_id = u.id
    WHERE pm.profile_id = ?
    ORDER BY pm.is_admin DESC, pm.joined_at ASC
  `).all([profileId]);
}
