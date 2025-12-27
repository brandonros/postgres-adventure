-- Sample data (inserted on primary, replicated to standby via streaming replication)

INSERT INTO users (id, email, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'john@example.com', 'John Smith'),
    ('11111111-1111-1111-1111-111111111112', 'jane@example.com', 'Jane Doe');

INSERT INTO orders (user_id, total_cents, status) VALUES
    ('11111111-1111-1111-1111-111111111111', 4999, 'completed'),
    ('11111111-1111-1111-1111-111111111111', 2500, 'pending');

INSERT INTO notes (user_id, content, metadata) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Short note', '{"priority": "low"}'),
    ('11111111-1111-1111-1111-111111111112', repeat('Large content for testing. ', 100), '{"priority": "high"}');
