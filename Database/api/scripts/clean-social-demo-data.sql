-- Limpia SOLO contenido social falso/demo.
-- No borra usuarios ni posts reales subidos desde la app.

BEGIN;

WITH demo_posts AS (
  SELECT p.id
  FROM "Post" p
  LEFT JOIN "User" u ON u.id = p."userId"
  WHERE p.image LIKE 'https://images.unsplash.com/%'
     OR u.email LIKE '%@fitconnect.local'
)
DELETE FROM "CommentLike" cl
WHERE cl."commentId" IN (
  SELECT c.id FROM "Comment" c WHERE c."postId" IN (SELECT id FROM demo_posts)
);

WITH demo_posts AS (
  SELECT p.id
  FROM "Post" p
  LEFT JOIN "User" u ON u.id = p."userId"
  WHERE p.image LIKE 'https://images.unsplash.com/%'
     OR u.email LIKE '%@fitconnect.local'
)
DELETE FROM "Comment" c
WHERE c."postId" IN (SELECT id FROM demo_posts);

WITH demo_posts AS (
  SELECT p.id
  FROM "Post" p
  LEFT JOIN "User" u ON u.id = p."userId"
  WHERE p.image LIKE 'https://images.unsplash.com/%'
     OR u.email LIKE '%@fitconnect.local'
)
DELETE FROM "Like" l
WHERE l."postId" IN (SELECT id FROM demo_posts);

WITH demo_posts AS (
  SELECT p.id
  FROM "Post" p
  LEFT JOIN "User" u ON u.id = p."userId"
  WHERE p.image LIKE 'https://images.unsplash.com/%'
     OR u.email LIKE '%@fitconnect.local'
)
DELETE FROM "Bookmark" b
WHERE b."postId" IN (SELECT id FROM demo_posts);

DELETE FROM "Highlight" h
WHERE h.image LIKE 'https://images.unsplash.com/%'
   OR h."storyImages"::text LIKE '%images.unsplash.com%';

DELETE FROM "Story" s
USING "User" u
WHERE u.id = s."userId"
  AND (
    s."imagePath" LIKE 'https://images.unsplash.com/%'
    OR u.email LIKE '%@fitconnect.local'
  );

WITH demo_posts AS (
  SELECT p.id
  FROM "Post" p
  LEFT JOIN "User" u ON u.id = p."userId"
  WHERE p.image LIKE 'https://images.unsplash.com/%'
     OR u.email LIKE '%@fitconnect.local'
)
DELETE FROM "Post" p
WHERE p.id IN (SELECT id FROM demo_posts);

DELETE FROM "Follow" f
USING "User" follower, "User" following_user
WHERE follower.id = f."followerId"
  AND following_user.id = f."followingId"
  AND (
    follower.email LIKE '%@fitconnect.local'
    OR following_user.email LIKE '%@fitconnect.local'
    OR f."followingId" IN (1, 2)
  );

COMMIT;
