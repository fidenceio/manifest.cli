const { logger } = require('../utils/logger');

const errorHandler = (err, req, res, next) => {
  // Log the error
  logger.logError('HTTP Request Error', err, {
    method: req.method,
    url: req.originalUrl,
    ip: req.ip,
    userAgent: req.get('User-Agent'),
    body: req.body,
    params: req.params,
    query: req.query
  });

  // Default error
  let error = {
    message: err.message || 'Internal Server Error',
    status: err.status || 500,
    timestamp: new Date().toISOString()
  };

  // Handle specific error types
  if (err.name === 'ValidationError') {
    error.status = 400;
    error.message = 'Validation Error';
    error.details = err.details || err.errors;
  } else if (err.name === 'UnauthorizedError') {
    error.status = 401;
    error.message = 'Unauthorized';
  } else if (err.name === 'ForbiddenError') {
    error.status = 403;
    error.message = 'Forbidden';
  } else if (err.name === 'NotFoundError') {
    error.status = 404;
    error.message = 'Resource Not Found';
  } else if (err.name === 'ConflictError') {
    error.status = 409;
    error.message = 'Resource Conflict';
  } else if (err.name === 'RateLimitError') {
    error.status = 429;
    error.message = 'Too Many Requests';
  }

  // Handle GitHub API errors
  if (err.status && err.status >= 400 && err.status < 500) {
    error.status = err.status;
    error.message = err.message || 'GitHub API Error';
    if (err.response && err.response.data) {
      error.details = err.response.data;
    }
  }

  // Handle Git operation errors
  if (err.message && err.message.includes('git')) {
    error.status = 400;
    error.message = 'Git Operation Failed';
    error.details = err.message;
  }

  // Handle Docker errors
  if (err.message && err.message.includes('docker')) {
    error.status = 500;
    error.message = 'Docker Operation Failed';
    error.details = err.message;
  }

  // In development, include stack trace
  if (process.env.NODE_ENV === 'development') {
    error.stack = err.stack;
  }

  // Send error response
  res.status(error.status).json({
    error: true,
    ...error
  });
};

module.exports = { errorHandler };
