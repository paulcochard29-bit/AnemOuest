// Storage wrapper — drop-in replacement for @vercel/blob using S3-compatible storage (Cloudflare R2)
// API matches @vercel/blob: put(), list(), del(), head()

import { S3Client, PutObjectCommand, ListObjectsV2Command, DeleteObjectCommand, HeadObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';

const s3 = new S3Client({
  region: 'auto',
  endpoint: process.env.R2_ENDPOINT,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

const BUCKET = process.env.R2_BUCKET || 'anemouest';
const PUBLIC_URL = process.env.R2_PUBLIC_URL || `${process.env.R2_ENDPOINT}/${BUCKET}`;

/**
 * put(pathname, body, options) → { url, pathname }
 * Compatible with @vercel/blob put()
 */
export async function put(pathname, body, options = {}) {
  const contentType = options.contentType || 'application/octet-stream';
  const bodyBuffer = typeof body === 'string' ? Buffer.from(body) : body;

  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: pathname,
    Body: bodyBuffer,
    ContentType: contentType,
  }));

  const url = `${PUBLIC_URL}/${pathname}`;
  return { url, pathname };
}

/**
 * list({ prefix, limit, cursor }) → { blobs: [{ url, pathname, uploadedAt }], cursor, hasMore }
 * Compatible with @vercel/blob list()
 */
export async function list(options = {}) {
  const { prefix, limit = 1000, cursor } = options;

  const result = await s3.send(new ListObjectsV2Command({
    Bucket: BUCKET,
    Prefix: prefix,
    MaxKeys: limit,
    ContinuationToken: cursor || undefined,
  }));

  const blobs = (result.Contents || []).map(obj => ({
    url: `${PUBLIC_URL}/${obj.Key}`,
    pathname: obj.Key,
    size: obj.Size,
    uploadedAt: obj.LastModified?.toISOString(),
  }));

  return {
    blobs,
    cursor: result.NextContinuationToken || null,
    hasMore: result.IsTruncated || false,
  };
}

/**
 * del(urlOrUrls) — delete one or multiple blobs
 * Compatible with @vercel/blob del()
 */
export async function del(urlOrUrls) {
  const urls = Array.isArray(urlOrUrls) ? urlOrUrls : [urlOrUrls];

  await Promise.all(urls.map(url => {
    const key = url.replace(`${PUBLIC_URL}/`, '');
    return s3.send(new DeleteObjectCommand({
      Bucket: BUCKET,
      Key: key,
    }));
  }));
}

/**
 * head(url) → { url, pathname, size, contentType, uploadedAt }
 * Compatible with @vercel/blob head()
 */
export async function head(url) {
  const key = url.replace(`${PUBLIC_URL}/`, '');

  try {
    const result = await s3.send(new HeadObjectCommand({
      Bucket: BUCKET,
      Key: key,
    }));
    return {
      url,
      pathname: key,
      size: result.ContentLength,
      contentType: result.ContentType,
      uploadedAt: result.LastModified?.toISOString(),
    };
  } catch {
    return null;
  }
}

/**
 * getBuffer(url) → Buffer
 * Helper to download blob content (not in @vercel/blob but useful)
 */
export async function getBuffer(url) {
  const key = url.replace(`${PUBLIC_URL}/`, '');

  const result = await s3.send(new GetObjectCommand({
    Bucket: BUCKET,
    Key: key,
  }));

  const chunks = [];
  for await (const chunk of result.Body) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
