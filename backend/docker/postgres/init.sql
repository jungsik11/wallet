CREATE TABLE IF NOT EXISTS chat_history (
    id SERIAL PRIMARY KEY,
    sender VARCHAR(50) NOT NULL, -- 'user' or 'ai'
    message TEXT NOT NULL,
    model_name VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
