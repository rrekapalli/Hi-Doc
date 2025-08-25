import { Router, Request as ExpressRequest, Response } from 'express';
import { db } from '../db.js';
import { logger } from '../logger.js';
import { randomUUID } from 'crypto';
import { interpretMessage } from '../ai.js';

// Extend Request type to include user
interface Request extends ExpressRequest {
	user?: {
		id: string;
		name?: string;
		email?: string;
	};
}

const profilesRouter = Router();

// Get all profiles for current user
profilesRouter.get('/api/profiles', async (req: Request, res: Response) => {
	try {
		const userId = req.user?.id;
		if (!userId) {
			return res.status(401).json({ error: 'Unauthorized' });
		}

		const profiles = db.prepare(`
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
				GROUP BY m.profile_id
			)
			SELECT 
				p.*,
				lm.content as last_message,
				lm.created_at as last_message_at,
				COALESCE(uc.count, 0) as unread_count
			FROM profiles p
			JOIN profile_members pm ON p.id = pm.profile_id
			LEFT JOIN latest_messages lm ON p.id = lm.profile_id AND lm.rn = 1
			LEFT JOIN unread_counts uc ON p.id = uc.profile_id
			WHERE pm.user_id = ?
			ORDER BY p.is_default DESC, lm.created_at DESC NULLS LAST
		`).all(userId, userId, userId);

		res.json(profiles);
	} catch (error) {
		logger.error('Error getting profiles:', error);
		res.status(500).json({ error: 'Failed to get profiles' });
	}
});

// Get messages for a profile
profilesRouter.get('/api/profiles/:id/messages', async (req: Request, res: Response) => {
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
			WHERE m.profile_id = ?
			ORDER BY m.created_at DESC
			LIMIT 50
		`).all(id);

		res.json(messages.reverse());
	} catch (error) {
		logger.error('Error getting profile messages:', error);
		res.status(500).json({ error: 'Failed to get profile messages' });
	}
});

// Send a message to a profile
profilesRouter.post('/api/profiles/:id/messages', async (req: Request, res: Response) => {
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

		db.prepare(`
			INSERT INTO messages (
				id, profile_id, sender_id, content, created_at
			) VALUES (?, ?, ?, ?, ?)
		`).run(messageId, id, userId, content, now);

		setTimeout(() => {
			processMessageWithAI(content, messageId, userId, id);
		}, 0);

		res.json({ id: messageId });
	} catch (error) {
		logger.error('Error sending profile message:', error);
		res.status(500).json({ error: 'Failed to send profile message' });
	}
});

async function processMessageWithAI(content: string, messageId: string, userId: string, profileId: string) {
	try {
		const interpretation = await interpretMessage(content);
		logger.debug('AI interpretation result', { interpretation, messageId });

		db.prepare(`
			UPDATE messages SET interpretation_json = ?, processed = 1
			WHERE id = ?
		`).run(JSON.stringify(interpretation), messageId);

		if (interpretation.reply) {
			const aiMessageId = randomUUID();
			db.prepare(`
				INSERT INTO messages (
					id, profile_id, sender_id, content, created_at, role
				) VALUES (?, ?, ?, ?, ?, ?)
			`).run(aiMessageId, profileId, userId, interpretation.reply, Date.now() + 1, 'assistant');
		}
	} catch (error) {
		logger.error('Error processing message with AI:', { error, messageId });
		db.prepare(`
			UPDATE messages SET processed = 1, interpretation_json = ?
			WHERE id = ?
		`).run(JSON.stringify({ parsed: false, reply: 'Failed to process', reasoning: String(error) }), messageId);
	}
}

export default profilesRouter;
