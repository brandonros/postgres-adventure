-- Node1 sample data: users created on dc1 (Atlanta)
INSERT INTO users (id, email, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'john@example.com', 'John Smith'),
    ('11111111-1111-1111-1111-111111111112', 'jane@example.com', 'Jane Doe');

-- Orders for node1 users
INSERT INTO orders (user_id, total_cents, status) VALUES
    ('11111111-1111-1111-1111-111111111111', 4999, 'completed'),
    ('11111111-1111-1111-1111-111111111111', 2500, 'pending');

-- Notes with varying sizes (small and large to test TOAST)
INSERT INTO notes (user_id, content, metadata) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Short note from dc1', '{"source": "dc1", "priority": "low"}'),
    ('11111111-1111-1111-1111-111111111112', repeat('This is a longer note that will be repeated to trigger TOAST storage. ', 100), '{"source": "dc1", "priority": "high", "tags": ["important", "toasted"]}');
