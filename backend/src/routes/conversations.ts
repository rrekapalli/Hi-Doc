import { Router, Request as ExpressRequest, Response } from 'express';
import { db } from '../db.js';
import { logger } from '../logger.js';
import { randomUUID } from 'crypto';
import { interpretMessage, AiInterpretation } from '../ai.js';

// Extend Request type to include user
interface Request extends ExpressRequest {
  user?: {
    id: string;
    name?: string;
    email?: string;
  };
}

const conversationsRouter = Router();

// Get all conversations for current user
conversationsRouter.get('/api/conversations', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const conversations = db.prepare(`
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
        GROUP BY m.conversation_id
      )
      SELECT 
        c.*,
        lm.content as last_message,
        lm.created_at as last_message_at,
        COALESCE(uc.count, 0) as unread_count
      FROM conversations c
      JOIN conversation_members cm ON c.id = cm.conversation_id
      LEFT JOIN latest_messages lm ON c.id = lm.conversation_id AND lm.rn = 1
      LEFT JOIN unread_counts uc ON c.id = uc.conversation_id
      WHERE cm.user_id = ?
      ORDER BY c.is_default DESC, lm.created_at DESC NULLS LAST
    `).all(userId, userId, userId);

    res.json(conversations);
  } catch (error) {
    logger.error('Error getting conversations:', error);
    res.status(500).json({ error: 'Failed to get conversations' });
  }
});

// Get messages for a conversation
conversationsRouter.get('/api/conversations/:id/messages', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const messages = db.prepare(`
      SELECT m.*, u.name as sender_name
      FROM messages m
      LEFT JOIN users u ON m.sender_id = u.id
      WHERE m.conversation_id = ?
      ORDER BY m.created_at DESC
      LIMIT 50
    `).all(id);

    res.json(messages.reverse());
  } catch (error) {
    logger.error('Error getting messages:', error);
    res.status(500).json({ error: 'Failed to get messages' });
  }
});

// Send a message
conversationsRouter.post('/api/conversations/:id/messages', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { content } = req.body;
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }

    const messageId = randomUUID();
    const now = Date.now();

    // Store user message first
    db.prepare(`
      INSERT INTO messages (
        id, conversation_id, sender_id, content, created_at
      ) VALUES (?, ?, ?, ?, ?)
    `).run(messageId, id, userId, content, now);

    // Process message with AI asynchronously (don't wait for completion)
    setTimeout(() => {
      processMessageWithAI(content, messageId, userId, id);
    }, 0);

    res.json({ id: messageId });
  } catch (error) {
    logger.error('Error sending message:', error);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// Process message with AI interpretation and store results
async function processMessageWithAI(content: string, messageId: string, userId: string, conversationId: string) {
  try {
    // Use the existing AI interpretation logic from ai.ts
    const interpretation = await interpretMessage(content);
    logger.debug('AI interpretation result', { interpretation, messageId });

    // Update message with interpretation and processed status
    db.prepare(`
      UPDATE messages SET interpretation_json = ?, processed = 1
      WHERE id = ?
    `).run(JSON.stringify(interpretation), messageId);

    // Add AI response message if there's a reply
    if (interpretation.reply) {
      const aiMessageId = randomUUID();
      db.prepare(`
        INSERT INTO messages (
          id, conversation_id, sender_id, content, created_at, role
        ) VALUES (?, ?, ?, ?, ?, ?)
      `).run(aiMessageId, conversationId, userId, interpretation.reply, Date.now() + 1, 'assistant');
    }
  } catch (error) {
    logger.error('Error processing message with AI:', { error, messageId });
    // Mark message as processed with error
    db.prepare(`
      UPDATE messages SET processed = 1, interpretation_json = ?
      WHERE id = ?
    `).run(JSON.stringify({ parsed: false, reply: 'Failed to process', reasoning: String(error) }), messageId);
  }
}

export default conversationsRouter;
