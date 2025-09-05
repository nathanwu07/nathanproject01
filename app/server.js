import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import { v4 as uuidv4 } from 'uuid';
import client from 'prom-client';
import pkg from 'pg';
import AWS from 'aws-sdk';

const { Pool } = pkg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Configuration via env
const PORT = process.env.PORT || 3000;
const STORAGE_BACKEND = (process.env.STORAGE_BACKEND || 's3').toLowerCase(); // 's3' | 'aurora'
const S3_BUCKET = process.env.S3_BUCKET || '';
const AWS_REGION = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'ap-southeast-1';

const DATABASE_URL = process.env.DATABASE_URL || '';
const PGHOST = process.env.PGHOST;
const PGPORT = process.env.PGPORT;
const PGDATABASE = process.env.PGDATABASE;
const PGUSER = process.env.PGUSER;
const PGPASSWORD = process.env.PGPASSWORD;

// Metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestCounter = new client.Counter({
  name: 'snake_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status']
});

const scoreSubmitCounter = new client.Counter({
  name: 'snake_scores_submitted_total',
  help: 'Total number of scores submitted'
});

const activeSessionsGauge = new client.Gauge({
  name: 'snake_active_sessions',
  help: 'Active sessions (approx)'
});

register.registerMetric(httpRequestCounter);
register.registerMetric(scoreSubmitCounter);
register.registerMetric(activeSessionsGauge);

// Simple in-memory fallback store
const memoryScores = [];

// DB / S3 clients
let pool = null;
let s3 = null;

if (STORAGE_BACKEND === 'aurora') {
  pool = new Pool(
    DATABASE_URL
      ? { connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } }
      : { host: PGHOST, port: Number(PGPORT || 5432), database: PGDATABASE, user: PGUSER, password: PGPASSWORD, ssl: { rejectUnauthorized: false } }
  );
} else {
  AWS.config.update({ region: AWS_REGION });
  s3 = new AWS.S3({ apiVersion: '2006-03-01' });
}

// Middleware to count requests
app.use((req, res, next) => {
  const end = res.end;
  res.end = function (...args) {
    try {
      httpRequestCounter.inc({ method: req.method, route: req.path, status: res.statusCode });
    } catch (_) {}
    end.apply(this, args);
  };
  next();
});

// Health endpoints
app.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));
app.get('/readyz', async (_req, res) => {
  try {
    if (STORAGE_BACKEND === 'aurora' && pool) {
      await pool.query('SELECT 1');
    } else if (STORAGE_BACKEND === 's3' && s3 && S3_BUCKET) {
      await s3.headBucket({ Bucket: S3_BUCKET }).promise();
    }
    res.status(200).json({ ready: true });
  } catch (err) {
    res.status(500).json({ ready: false, error: String(err) });
  }
});

// Metrics endpoint
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Scores API
app.get('/api/scores', async (_req, res) => {
  try {
    if (STORAGE_BACKEND === 'aurora' && pool) {
      const { rows } = await pool.query('SELECT id, user_id, points, created_at FROM scores ORDER BY created_at DESC LIMIT 50');
      return res.json(rows);
    }
    if (STORAGE_BACKEND === 's3' && s3 && S3_BUCKET) {
      // List last 50 objects under scores/ and fetch
      const list = await s3.listObjectsV2({ Bucket: S3_BUCKET, Prefix: 'scores/' }).promise();
      const items = (list.Contents || []).sort((a, b) => (b.LastModified || 0) - (a.LastModified || 0)).slice(0, 50);
      const results = await Promise.all(
        items.map(async (obj) => {
          const data = await s3.getObject({ Bucket: S3_BUCKET, Key: obj.Key }).promise();
          return JSON.parse(data.Body.toString('utf-8'));
        })
      );
      return res.json(results);
    }
    // fallback
    return res.json(memoryScores.slice(-50).reverse());
  } catch (err) {
    return res.status(500).json({ error: String(err) });
  }
});

app.post('/api/scores', async (req, res) => {
  try {
    const { user_id, points } = req.body || {};
    if (typeof points !== 'number') {
      return res.status(400).json({ error: 'points must be a number' });
    }
    const id = uuidv4();
    const now = new Date();
    scoreSubmitCounter.inc();
    const record = { id, user_id: user_id || 'anonymous', points, created_at: now.toISOString() };

    if (STORAGE_BACKEND === 'aurora' && pool) {
      await pool.query(
        'INSERT INTO scores (id, user_id, points, created_at) VALUES ($1, $2, $3, $4)',
        [id, record.user_id, points, now.toISOString()]
      );
      return res.status(201).json(record);
    }
    if (STORAGE_BACKEND === 's3' && s3 && S3_BUCKET) {
      const key = `scores/${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, '0')}/${String(now.getUTCDate()).padStart(2, '0')}/${id}.json`;
      await s3
        .putObject({ Bucket: S3_BUCKET, Key: key, Body: JSON.stringify(record), ContentType: 'application/json' })
        .promise();
      return res.status(201).json(record);
    }
    memoryScores.push(record);
    return res.status(201).json(record);
  } catch (err) {
    return res.status(500).json({ error: String(err) });
  }
});

// Simple session gauge endpoints (optional usage from frontend)
app.post('/api/session/start', (_req, res) => {
  activeSessionsGauge.inc();
  res.status(200).json({ ok: true });
});
app.post('/api/session/end', (_req, res) => {
  activeSessionsGauge.dec();
  res.status(200).json({ ok: true });
});

// Serve frontend
app.get('/', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Snake Game server listening on :${PORT} (backend=${STORAGE_BACKEND})`);
});


