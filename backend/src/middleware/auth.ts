import { Request as ExpressRequest, Response, NextFunction } from 'express';

// Extend Express Request to include user
interface Request extends ExpressRequest {
  user?: {
    id: string;
    name?: string;
    email?: string;
  };
}

export const authMiddleware = (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;
  
  // For development: allow a special dev token
  if (authHeader?.startsWith('Bearer dev_test_token_')) {
    const userId = authHeader.replace('Bearer dev_test_token_', '');
    req.user = { id: userId };
    return next();
  }

  // Skip auth for certain routes
  if (req.path === '/healthz' || req.path === '/api/auth/dev-login') {
    return next();
  }

  // Check if we're in dev mode and using prototype user
  if (process.env.NODE_ENV !== 'production' && req.path.startsWith('/api/admin/')) {
    req.user = { id: 'prototype-user-12345' };
    return next();
  }

  // Require auth for all other routes
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token provided' });
  }

  // TODO: Add real JWT verification here once we implement proper auth
  // const token = authHeader.split(' ')[1];
  // try {
  //   const decoded = verifyToken(token);
  //   req.user = decoded;
  //   next();
  // } catch (error) {
  //   return res.status(401).json({ error: 'Invalid token' });
  // }

  // For now, just extract user ID from token
  const userId = authHeader.replace('Bearer ', '');
  req.user = { id: userId };
  next();
};
