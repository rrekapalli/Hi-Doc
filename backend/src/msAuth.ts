import { createRemoteJWKSet, jwtVerify, JWTPayload } from 'jose';
import { URL } from 'url';

const tenant = process.env.MS_TENANT || 'common';
const jwksUri = new URL(`https://login.microsoftonline.com/${tenant}/discovery/v2.0/keys`);
const JWKS = createRemoteJWKSet(jwksUri);

export interface MicrosoftClaims extends JWTPayload {
  email?: string;
  preferred_username?: string;
  name?: string;
  oid?: string; // object id
}

export async function verifyMicrosoftIdToken(idToken: string): Promise<MicrosoftClaims> {
  const { payload } = await jwtVerify(idToken, JWKS, {
    algorithms: ['RS256'],
  });
  return payload as MicrosoftClaims;
}
