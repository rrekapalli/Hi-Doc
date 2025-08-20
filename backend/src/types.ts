export interface DbMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  user_id: string;
  role: string;
  content: string;
  created_at: number;
  interpretation_json?: string;
  processed: number;
  stored_record_id?: string;
}
