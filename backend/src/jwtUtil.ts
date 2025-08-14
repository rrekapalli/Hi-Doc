import { createSecretKey } from 'crypto';
import { SignJWT, jwtVerify } from 'jose';

const SECRET = process.env.JWT_SECRET || 'dev-insecure-secret-change';
const key = createSecretKey(Buffer.from(SECRET));

export interface TokenPayload {
  uid: string;
  email: string;
}

export async function signToken(payload: TokenPayload, expiresIn = '12h') {
  return await new SignJWT(payload as any)
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(key);
}

export async function verifyToken(token: string): Promise<TokenPayload> {
  const { payload } = await jwtVerify(token, key, { algorithms: ['HS256'] });
  return payload as unknown as TokenPayload;
}
