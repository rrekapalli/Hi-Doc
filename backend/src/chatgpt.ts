import { OpenAI } from 'openai';
import { logger } from './logger.js';

if (!process.env.OPENAI_API_KEY) {
  throw new Error('OPENAI_API_KEY environment variable is not set');
}

export class ChatGptService {
  private openai: OpenAI;

  constructor() {
    this.openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });
  }

  async chat(
    messages: { role: 'system' | 'user' | 'assistant'; content: string | any[] }[],
    model: string = 'gpt-3.5-turbo'
  ): Promise<string> {
    try {
      const completion = await this.openai.chat.completions.create({
        model: model,
        messages: messages as any,
        max_tokens: 4000, // Increased for complex medical reports
      });

      const content = completion.choices[0].message.content;
      if (!content) {
        throw new Error('Empty response from ChatGPT');
      }
      return content;
    } catch (error) {
      logger.error('ChatGPT API error:', error);
      throw error;
    }
  }
}
