#!/usr/bin/env node

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const dotenv = require('dotenv');
const { logger } = require('./utils/logger');
const { errorHandler } = require('./middleware/errorHandler');
const { rateLimiter } = require('./middleware/rateLimiter');

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Rate limiting
app.use(rateLimiter);

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: require('../package.json').version
  });
});

// API Routes
app.use('/api/v1/version', require('./routes/version'));
app.use('/api/v1/documentation', require('./routes/documentation'));
app.use('/api/v1/git', require('./routes/git'));
app.use('/api/v1/github', require('./routes/github'));
app.use('/api/v1/updates', require('./routes/updates'));
app.use('/api/v1/repositories', require('./routes/repositories'));
app.use('/api/v1/manifest', require('./routes/manifest'));
app.use('/api/v1/heartbeat', require('./routes/heartbeat'));
app.use('/api/v1/plugins', require('./routes/plugins'));
// LLM Agent functionality moved to Manifest Cloud service
// app.use('/api/v1/llm-agent', require('./routes/llmAgent'));

// Error handling
app.use(errorHandler);

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Route ${req.originalUrl} not found`,
    timestamp: new Date().toISOString()
  });
});

// Start server
app.listen(PORT, () => {
  logger.info(`🚀 Manifest service started on port ${PORT}`);
  logger.info(`📚 API Documentation available at http://localhost:${PORT}/api/v1/documentation`);
  logger.info(`🏥 Health check available at http://localhost:${PORT}/health`);
  logger.info(`🤖 LLM Agent capabilities moved to Manifest Cloud service`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  process.exit(0);
});

module.exports = app;
