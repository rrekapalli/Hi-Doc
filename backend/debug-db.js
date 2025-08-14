import Database from 'better-sqlite3';

const db = new Database('./hi_doc.db');

console.log('Users table:');
const users = db.prepare('SELECT * FROM users').all();
console.log(users);

console.log('\nMessages table (last 5):');
const messages = db.prepare('SELECT * FROM messages ORDER BY created_at DESC LIMIT 5').all();
console.log(messages);

db.close();