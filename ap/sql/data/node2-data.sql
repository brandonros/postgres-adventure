-- Node2 sample data: users created on dc2 (Dallas)
INSERT INTO users (id, email, name) VALUES
    ('22222222-2222-2222-2222-222222222221', 'mary@example.com', 'Mary Johnson'),
    ('22222222-2222-2222-2222-222222222222', 'bob@example.com', 'Bob Williams');

-- INTENTIONAL CONFLICT: Same UUID as node1's John Smith, but different data.
-- This row will conflict with node1's version during replication.
--
-- What happens with each conflict_resolution setting:
--   'error'            - Replication STOPS. node1 has "John Smith", node2 has "John Smithson".
--                        Manual intervention required. Data is inconsistent until fixed.
--   'apply_remote'     - node1 wins on node2 (becomes "John Smith"),
--                        node2 wins on node1 (becomes "John Smithson").
--                        BOTH nodes end up with "John Smithson" (last to replicate wins).
--   'keep_local'       - Each node keeps its own version. node1 stays "John Smith",
--                        node2 stays "John Smithson". Data is PERMANENTLY inconsistent.
--   'last_update_wins' - Whichever INSERT happened later (by commit timestamp) wins on BOTH nodes.
--                        Consistent, but one version silently disappears.
INSERT INTO users (id, email, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'john_dc2@example.com', 'John Smithson');

-- Orders for node2 users
INSERT INTO orders (user_id, total_cents, status) VALUES
    ('22222222-2222-2222-2222-222222222221', 15000, 'completed'),
    ('22222222-2222-2222-2222-222222222222', 750, 'cancelled');

-- Notes with varying sizes (small and large to test TOAST)
INSERT INTO notes (user_id, content, metadata) VALUES
    ('22222222-2222-2222-2222-222222222221', 'Quick note from dc2', '{"source": "dc2", "priority": "medium"}'),
    ('22222222-2222-2222-2222-222222222222', repeat('Large content blob from the Dallas datacenter for TOAST testing purposes. ', 100), '{"source": "dc2", "priority": "low", "tags": ["bulk", "toasted"]}');
