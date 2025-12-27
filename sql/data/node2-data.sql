-- Node2 sample data: users created on dc2 (Dallas)
INSERT INTO users (id, email, name) VALUES
    ('22222222-2222-2222-2222-222222222221', 'mary@example.com', 'Mary Johnson'),
    ('22222222-2222-2222-2222-222222222222', 'bob@example.com', 'Bob Williams');

-- Orders for node2 users
INSERT INTO orders (user_id, total_cents, status) VALUES
    ('22222222-2222-2222-2222-222222222221', 15000, 'completed'),
    ('22222222-2222-2222-2222-222222222222', 750, 'cancelled');

-- Notes with varying sizes (small and large to test TOAST)
INSERT INTO notes (user_id, content, metadata) VALUES
    ('22222222-2222-2222-2222-222222222221', 'Quick note from dc2', '{"source": "dc2", "priority": "medium"}'),
    ('22222222-2222-2222-2222-222222222222', repeat('Large content blob from the Dallas datacenter for TOAST testing purposes. ', 100), '{"source": "dc2", "priority": "low", "tags": ["bulk", "toasted"]}');
